import Foundation

extension String {
    /// Turns a JSON key into a label: `startTime` and `start_time` both become "Start time".
    var humanizedFieldName: String {
        var words: [String] = []
        var current = ""
        for character in self {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let last = current.last, last.isLowercase || last.isNumber {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        guard let first = words.first else { return self }
        let rest = words.dropFirst().map { $0.lowercased() }
        return ([first.prefix(1).uppercased() + first.dropFirst().lowercased()] + rest).joined(separator: " ")
    }
}
