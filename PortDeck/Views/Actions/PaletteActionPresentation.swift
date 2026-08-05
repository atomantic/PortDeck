import SwiftUI

extension PaletteAction {
    /// Icon and tint for an action, shared by the list row and the detail header so the
    /// same action never reads as two different kinds of thing.
    var presentation: (icon: String, tint: Color) {
        if destructive == true { return ("exclamationmark.triangle", .portWarning) }
        if isReader { return ("list.bullet.rectangle", .portAccent) }
        return ("bolt.fill", .portViolet)
    }
}
