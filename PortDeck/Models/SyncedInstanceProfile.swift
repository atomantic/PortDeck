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

    private enum CodingKeys: String, CodingKey {
        case localID, baseURLString, localLabel, instanceID, remoteName, hostname, version
        case authRequired, addedAt, updatedAt, deletedAt
        case updatedAtReferenceTime, deletedAtReferenceTime
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        localID = try values.decode(UUID.self, forKey: .localID)
        baseURLString = try values.decode(String.self, forKey: .baseURLString)
        localLabel = try values.decode(String.self, forKey: .localLabel)
        instanceID = try values.decodeIfPresent(String.self, forKey: .instanceID)
        remoteName = try values.decode(String.self, forKey: .remoteName)
        hostname = try values.decode(String.self, forKey: .hostname)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        authRequired = try values.decode(Bool.self, forKey: .authRequired)
        addedAt = try values.decode(Date.self, forKey: .addedAt)
        // Keep the old date fields readable, but order conflicts using the exact
        // reference-time Double rather than ISO 8601's whole-second representation.
        if let precise = try values.decodeIfPresent(Double.self, forKey: .updatedAtReferenceTime) {
            updatedAt = Date(timeIntervalSinceReferenceDate: precise)
        } else {
            updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        }
        if let precise = try values.decodeIfPresent(Double.self, forKey: .deletedAtReferenceTime) {
            deletedAt = Date(timeIntervalSinceReferenceDate: precise)
        } else {
            deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(localID, forKey: .localID)
        try values.encode(baseURLString, forKey: .baseURLString)
        try values.encode(localLabel, forKey: .localLabel)
        try values.encodeIfPresent(instanceID, forKey: .instanceID)
        try values.encode(remoteName, forKey: .remoteName)
        try values.encode(hostname, forKey: .hostname)
        try values.encodeIfPresent(version, forKey: .version)
        try values.encode(authRequired, forKey: .authRequired)
        try values.encode(addedAt, forKey: .addedAt)
        // Older clients ignore the additive keys and still decode these dates.
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try values.encode(updatedAt.timeIntervalSinceReferenceDate, forKey: .updatedAtReferenceTime)
        try values.encodeIfPresent(deletedAt?.timeIntervalSinceReferenceDate, forKey: .deletedAtReferenceTime)
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
