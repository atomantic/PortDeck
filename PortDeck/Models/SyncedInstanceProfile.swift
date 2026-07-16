import Foundation

struct SyncedInstanceProfile: Codable, Equatable, Sendable {
    let localID: UUID
    let baseURLString: String
    let localLabel: String
    let instanceID: String?
    let remoteName: String
    let hostname: String
    let version: String?
    let authRequired: Bool
    let addedAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(instance: PortOSInstance, deletedAt: Date? = nil) {
        localID = instance.localID
        baseURLString = instance.baseURLString
        localLabel = instance.localLabel
        instanceID = instance.instanceID
        remoteName = instance.remoteName
        hostname = instance.hostname
        version = instance.version
        authRequired = instance.authRequired
        addedAt = instance.addedAt
        updatedAt = instance.syncUpdatedAt
        self.deletedAt = deletedAt
    }

    var effectiveDate: Date { deletedAt ?? updatedAt }
    var isDeleted: Bool { deletedAt != nil }
}

struct FleetSyncSummary: Equatable, Sendable {
    let imported: Int
    let updated: Int
    let deleted: Int

    static let noChanges = FleetSyncSummary(imported: 0, updated: 0, deleted: 0)

    var description: String {
        let total = imported + updated + deleted
        return total == 0 ? "Fleet is up to date." : "Synced \(total) fleet change\(total == 1 ? "" : "s")."
    }
}
