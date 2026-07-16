import Foundation
import SwiftData

@MainActor
struct FleetSyncCoordinator {
    let store: any FleetSyncStore
    let credentials: any CredentialStore

    func synchronize(modelContext: ModelContext) throws -> FleetSyncSummary {
        let localInstances = try modelContext.fetch(FetchDescriptor<PortOSInstance>())
        let localByID = Dictionary(uniqueKeysWithValues: localInstances.map { ($0.localID, $0) })
        var winners = Dictionary(uniqueKeysWithValues: try store.loadProfiles().map { ($0.localID, $0) })

        for instance in localInstances {
            let local = SyncedInstanceProfile(instance: instance)
            if let remote = winners[instance.localID], remote.effectiveDate > local.effectiveDate { continue }
            winners[instance.localID] = local
        }

        var imported = 0
        var updated = 0
        var deleted = 0
        for record in winners.values {
            if record.isDeleted {
                if let local = localByID[record.localID], record.effectiveDate >= local.syncUpdatedAt {
                    try credentials.removePassword(for: local.localID)
                    modelContext.delete(local)
                    deleted += 1
                }
                continue
            }
            if let local = localByID[record.localID] {
                if record.updatedAt > local.syncUpdatedAt {
                    local.apply(syncedProfile: record)
                    updated += 1
                }
            } else {
                modelContext.insert(PortOSInstance(syncedProfile: record))
                imported += 1
            }
        }

        try modelContext.save()
        try store.saveProfiles(Array(winners.values))
        return FleetSyncSummary(imported: imported, updated: updated, deleted: deleted)
    }

    func recordDeletion(_ instance: PortOSInstance) throws {
        var profiles = Dictionary(uniqueKeysWithValues: try store.loadProfiles().map { ($0.localID, $0) })
        profiles[instance.localID] = SyncedInstanceProfile(instance: instance, deletedAt: .now)
        try store.saveProfiles(Array(profiles.values))
    }
}
