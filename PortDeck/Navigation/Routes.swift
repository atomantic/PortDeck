import Foundation
import SwiftData

enum SessionRoute: Hashable {
    case list
    case detail(PersistentIdentifier)
    case recording
}

enum MemoryRoute: Hashable {
    case list
    case detail(PersistentIdentifier)
}
