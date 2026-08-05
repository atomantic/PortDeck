import Foundation

/// A palette action result reshaped for rendering.
///
/// PortOS tools return free-form JSON — `items`, `hits`, `goals`, `events`,
/// `content` — alongside a one-line `summary`. Showing only the summary threw the
/// payload away ("Last 5 captures." with no captures), so this picks the primary
/// collection out of the envelope and turns it into rows, keeps long-form strings
/// as passages, and lists whatever scalars remain as facts. Nothing is dropped:
/// the raw JSON stays available for anything this shaping does not anticipate.
struct ActionResultDisplay: Equatable, Sendable {
    struct Field: Equatable, Sendable, Identifiable {
        /// The payload's own key. Two keys can humanize to the same label (`userId` and
        /// `user_id` both read "User id"), and `ForEach` needs the identity to stay unique.
        let id: String
        let label: String
        let value: String

        init(key: String, value: String) {
            id = key
            label = key.humanizedFieldName
            self.value = value
        }
    }

    struct Row: Equatable, Sendable, Identifiable {
        let id: Int
        let title: String
        let subtitle: String?
        let fields: [Field]
    }

    /// The tool's own one-line description of what it did.
    let summary: String?
    /// `true` when the envelope or the tool reported failure, even under HTTP 200.
    let isFailure: Bool
    /// Label of the collection the rows came from, e.g. "Items" or "Events".
    let collectionLabel: String?
    let rows: [Row]
    let passages: [Field]
    let facts: [Field]
    private let result: JSONValue

    /// `true` when the payload carried a list — an empty one still means "no entries",
    /// which is different from a result that was never list-shaped.
    var hasCollection: Bool { collectionLabel != nil }

    /// Rendered on demand: the raw view is behind a collapsed disclosure, and every page
    /// of a growing list would otherwise re-encode the whole payload.
    var rawJSON: String { result.prettyPrinted }

    init(result: JSONValue, envelopeOK: Bool = true) {
        let object = result.objectValue ?? [:]
        let collection = Self.primaryCollection(result: result, object: object)
        let passageKeys = Self.passageKeys(in: object)

        summary = result.summary
        isFailure = !envelopeOK || result.okFlag == false
        collectionLabel = collection.map { $0.key.humanizedFieldName }
        rows = Self.makeRows(from: collection?.values ?? [])
        passages = passageKeys.sorted().map {
            Field(key: $0, value: object[$0]?.stringValue ?? "")
        }
        facts = object
            .filter { key, _ in
                !Self.hiddenKeys.contains(key) && key != collection?.key && !passageKeys.contains(key)
            }
            .map { Field(key: $0.key, value: Self.displayString($0.value)) }
            .filter { !$0.value.isEmpty }
            .sorted { $0.label < $1.label }
        self.result = result
    }

    // MARK: - Shaping

    /// Keys checked first when several arrays could be the payload's primary list.
    private static let collectionPriority = [
        "items", "hits", "entries", "results", "events", "goals", "processes",
        "records", "matches", "list", "data"
    ]
    private static let titleKeys = ["title", "text", "name", "label", "question", "content", "summary", "message"]
    private static let subtitleKeys = ["date", "time", "when", "startTime", "timestamp", "createdAt", "capturedAt"]
    /// String fields rendered as paragraphs rather than one-line facts.
    private static let longFormKeys: Set<String> = ["content", "answer", "body", "output", "detail", "details", "notes"]
    private static let hiddenKeys: Set<String> = ["ok", "summary", "success"]
    private static let longFormLength = 140
    private static let factValueLimit = 240

    private static func primaryCollection(
        result: JSONValue,
        object: [String: JSONValue]
    ) -> (key: String, values: [JSONValue])? {
        if let topLevel = result.arrayValue { return (key: "results", values: topLevel) }
        let arrays = object
            .compactMap { key, value in value.arrayValue.map { (key: key, values: $0) } }
            .sorted { lhs, rhs in
                let left = collectionPriority.firstIndex(of: lhs.key) ?? Int.max
                let right = collectionPriority.firstIndex(of: rhs.key) ?? Int.max
                return left == right ? lhs.key < rhs.key : left < right
            }
        // A known payload key wins even when it came back empty — an empty `items` means
        // "no entries", and letting an incidental non-empty array (`tags`) take its place
        // would render the wrong list and hide the empty state.
        if let known = arrays.first(where: { collectionPriority.contains($0.key) }) { return known }
        return arrays.first { !$0.values.isEmpty } ?? arrays.first
    }

    private static func passageKeys(in object: [String: JSONValue]) -> Set<String> {
        Set(object.compactMap { key, value in
            guard !hiddenKeys.contains(key), let text = value.stringValue, !text.isEmpty else { return nil }
            return longFormKeys.contains(key) || text.count > longFormLength ? key : nil
        })
    }

    private static func makeRows(from values: [JSONValue]) -> [Row] {
        values.enumerated().map { index, value in
            guard let object = value.objectValue else {
                return Row(id: index, title: displayString(value), subtitle: nil, fields: [])
            }
            let titleKey = titleKeys.first { object[$0]?.stringValue?.isEmpty == false }
                ?? object.keys.sorted().first { object[$0]?.isScalar == true }
            let subtitleKey = subtitleKeys.first { key in
                key != titleKey && object[key]?.stringValue?.isEmpty == false
            }
            let fields = object
                .filter { key, _ in key != titleKey && key != subtitleKey && !hiddenKeys.contains(key) }
                .map { Field(key: $0.key, value: displayString($0.value)) }
                .filter { !$0.value.isEmpty }
                .sorted { $0.label < $1.label }
            return Row(
                id: index,
                title: titleKey.map { displayString(object[$0] ?? .null) } ?? "Entry \(index + 1)",
                subtitle: subtitleKey.flatMap { object[$0]?.stringValue }.map { humanizeTimestamp($0) },
                fields: fields
            )
        }
    }

    // MARK: - Value formatting

    static func displayString(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): humanizeTimestamp(text)
        case .number(let number): number == number.rounded() && abs(number) < 1e15
            ? String(Int(number))
            : String(format: "%g", number)
        case .bool(let flag): flag ? "Yes" : "No"
        case .null: ""
        case .object, .array: truncate(value.compactJSON)
        }
    }

    private static func truncate(_ text: String) -> String {
        text.count <= factValueLimit ? text : String(text.prefix(factValueLimit)) + "…"
    }

    /// Renders ISO dates and timestamps as readable text, leaving other strings untouched.
    static func humanizeTimestamp(_ raw: String) -> String {
        if raw.count == 10, let date = dayFormatter.date(from: raw) {
            return dayDisplayFormatter.string(from: date)
        }
        if raw.count >= 19, let date = parseTimestamp(raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        if let date = isoFormatter.date(from: raw) ?? isoFractionalFormatter.date(from: raw) { return date }
        // Zone-less timestamps (`2026-08-05T18:36:22`) come out of SQL columns and fail
        // ISO8601DateFormatter, which requires an offset. Read them as local time.
        return raw.count == 19 ? zonelessFormatter.date(from: raw) : nil
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Date-only values carry no zone, so they are rendered in UTC to stay on the day PortOS meant.
    private static let dayDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let zonelessFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
