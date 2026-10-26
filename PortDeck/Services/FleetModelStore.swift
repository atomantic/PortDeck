import Foundation
import SwiftData

enum FleetModelStore {
    @MainActor
    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        if !configuration.isStoredInMemoryOnly {
            // SwiftData's default store can reach CoreData before Application Support
            // exists on first launch. Keep its resolved URL, including existing stores.
            try FileManager.default.createDirectory(
                at: configuration.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        return try ModelContainer(for: PortOSInstance.self, configurations: configuration)
    }
}
