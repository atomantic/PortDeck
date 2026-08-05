import Foundation

/// How PortDeck presents a palette action.
///
/// The PortOS palette manifest does not label actions read vs. write, so PortDeck
/// infers it from the id. An action is treated as a *reader* — safe to fetch when its
/// page opens, and safe to re-fetch with a wider window — only when all of these hold:
///
/// 1. one of its id components is a read verb (`list`, `status`, `search`, `now`, …),
/// 2. none of its id components is a write verb, and
/// 3. PortOS did not flag it destructive.
///
/// Both verb lists matter. A read verb alone would auto-invoke `backup_now` and
/// `feeds_mark_read`; absent required parameters alone would auto-invoke `timer_set`,
/// which takes none and still creates a timer. Anything neither list recognizes stays a
/// manual Run form, so an unknown future action fails closed.
extension PaletteAction {
    private static let readVerbs: Set<String> = [
        "digest", "get", "history", "info", "list", "lookup", "next", "now",
        "read", "recent", "search", "show", "stats", "status", "summary",
        "today", "upcoming", "view"
    ]

    private static let writeVerbs: Set<String> = [
        "add", "append", "apply", "archive", "assign", "backup", "cancel", "capture",
        "claim", "clear", "commit", "create", "delete", "deploy", "disable", "dismiss",
        "dispatch", "drain", "edit", "enable", "execute", "export", "flush", "generate",
        "import", "install", "invoke", "kill", "mark", "merge", "migrate", "move",
        "pause", "post", "prune", "publish", "purge", "push", "reboot", "rebuild",
        "reindex", "reload", "remove", "rename", "replace", "reset", "restart",
        "restore", "resume", "revert", "revoke", "rollback", "rotate", "run", "save",
        "schedule", "seed", "send", "set", "snooze", "start", "stop", "subscribe",
        "switch", "sync", "toggle", "trigger", "unassign", "unsubscribe", "update",
        "upgrade", "upload", "wipe", "write"
    ]

    /// PortOS list tools all name their page size `limit`; nothing else is assumed to be one.
    private static let pageSizeParameterName = "limit"

    func isRequired(_ parameterName: String) -> Bool {
        parameters.required?.contains(parameterName) == true
    }

    /// True when the id reads like a query rather than a mutation, whatever it asks for as input.
    ///
    /// Re-running one of these is safe, which is what makes scroll paging safe: widening the
    /// window re-invokes the action, and doing that to a writer would repeat its side effect.
    var isReadShaped: Bool {
        guard destructive != true else { return false }
        // Humanizing splits on separators *and* camel-case boundaries, so a `listRecent`
        // or `recent_clearAll` id tokenizes the same way a snake_case one does.
        let components = id
            .replacingOccurrences(of: ".", with: "_")
            .humanizedFieldName
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        guard !components.contains(where: Self.writeVerbs.contains) else { return false }
        return components.contains(where: Self.readVerbs.contains)
    }

    /// True when opening the action should fetch immediately instead of waiting for a Run tap.
    var isReader: Bool { isReadShaped && parameters.required?.isEmpty != false }

    /// The integer parameter that widens the result window, when the action has one.
    var pageSizeParameterName: String? {
        guard let parameter = parameters.properties[Self.pageSizeParameterName],
              parameter.type == "integer" || parameter.type == "number" else { return nil }
        return Self.pageSizeParameterName
    }

    /// Parameters sorted required-first, then alphabetically, so the form order is stable.
    var orderedParameters: [(name: String, parameter: ActionParameter)] {
        let required = Set(parameters.required ?? [])
        return parameters.properties
            .map { (name: $0.key, parameter: $0.value) }
            .sorted { lhs, rhs in
                let leftRequired = required.contains(lhs.name)
                let rightRequired = required.contains(rhs.name)
                if leftRequired != rightRequired { return leftRequired }
                return lhs.name < rhs.name
            }
    }
}
