import Foundation
import SwiftData

@Model
final class Participant {
    var name: String = ""
    var notes: String = ""

    @Relationship(deleteRule: .nullify)
    var sessions: [Session]? = nil

    init(name: String = "", notes: String = "") {
        self.name = name
        self.notes = notes
    }
}
