import Foundation
import SwiftData

enum InstanceConnectionState: String, Codable, CaseIterable {
    case unknown
    case checking
    case online
    case needsPassword
    case offline
}

@Model
final class PortOSInstance {
    @Attribute(.unique) var localID: UUID
    var baseURLString: String
    var localLabel: String
    var instanceID: String?
    var remoteName: String
    var hostname: String
    var version: String?
    var authRequired: Bool
    var connectionStateRaw: String
    var lastCheckedAt: Date?
    var lastReachableAt: Date?
    var lastError: String?
    var addedAt: Date
    var syncUpdatedAt: Date = Date.now

    init(
        localID: UUID = UUID(),
        baseURL: URL,
        localLabel: String = "",
        health: PortOSHealth,
        addedAt: Date = .now
    ) {
        self.localID = localID
        self.baseURLString = baseURL.absoluteString
        self.localLabel = localLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        instanceID = health.instanceID
        remoteName = health.name
        hostname = health.hostname
        version = health.version
        authRequired = health.authRequired
        connectionStateRaw = InstanceConnectionState.online.rawValue
        lastCheckedAt = addedAt
        lastReachableAt = addedAt
        lastError = nil
        self.addedAt = addedAt
        syncUpdatedAt = addedAt
    }

    init(syncedProfile: SyncedInstanceProfile) {
        localID = syncedProfile.localID
        baseURLString = syncedProfile.baseURLString
        localLabel = syncedProfile.localLabel
        instanceID = syncedProfile.instanceID
        remoteName = syncedProfile.remoteName
        hostname = syncedProfile.hostname
        version = syncedProfile.version
        authRequired = syncedProfile.authRequired
        connectionStateRaw = InstanceConnectionState.unknown.rawValue
        lastCheckedAt = nil
        lastReachableAt = nil
        lastError = nil
        addedAt = syncedProfile.addedAt
        syncUpdatedAt = syncedProfile.updatedAt
    }

    var baseURL: URL? { URL(string: baseURLString) }

    var displayName: String {
        let trimmedLabel = localLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty { return trimmedLabel }
        if !remoteName.isEmpty { return remoteName }
        if !hostname.isEmpty { return hostname }
        return baseURL?.host ?? "PortOS"
    }

    var connectionState: InstanceConnectionState {
        get { InstanceConnectionState(rawValue: connectionStateRaw) ?? .unknown }
        set { connectionStateRaw = newValue.rawValue }
    }

    func apply(health: PortOSHealth, checkedAt: Date = .now) {
        instanceID = health.instanceID
        remoteName = health.name
        hostname = health.hostname
        version = health.version
        if health.authRequiredWasReported { authRequired = health.authRequired }
        lastCheckedAt = checkedAt
        lastReachableAt = checkedAt
        lastError = nil
        connectionState = .online
    }

    func markFailure(_ error: Error, checkedAt: Date = .now) {
        lastCheckedAt = checkedAt
        lastError = error.localizedDescription
        connectionState = (error as? PortOSAPIError) == .authenticationRequired
            ? .needsPassword
            : .offline
    }

    func apply(syncedProfile: SyncedInstanceProfile) {
        baseURLString = syncedProfile.baseURLString
        localLabel = syncedProfile.localLabel
        instanceID = syncedProfile.instanceID
        remoteName = syncedProfile.remoteName
        hostname = syncedProfile.hostname
        version = syncedProfile.version
        authRequired = syncedProfile.authRequired
        addedAt = syncedProfile.addedAt
        syncUpdatedAt = syncedProfile.updatedAt
    }

    func markSyncMetadataChanged(at date: Date = .now) {
        syncUpdatedAt = date
    }
}
