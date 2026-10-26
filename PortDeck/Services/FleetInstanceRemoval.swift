import Foundation

/// Captures the secure-state policy before removal, independently of model persistence.
enum FleetInstanceRemoval {
    case directCredential(UUID, any CredentialStore)
    case devicePairing(UUID, TailcatTunnelPool, previous: TailcatConnection?)

    init(instance: PortOSInstance, credentials: any CredentialStore, tailcat: TailcatTunnelPool) throws {
        let id = instance.localID
        if instance.usesTailcat {
            self = .devicePairing(id, tailcat, previous: try tailcat.store.connection(for: id))
        } else {
            self = .directCredential(id, credentials)
        }
    }

    /// Compensation becomes available only after secure removal succeeds.
    func removeSecureState() throws -> Compensation {
        switch self {
        case let .directCredential(id, credentials):
            try credentials.removePassword(for: id)
            // Direct passwords deliberately remain absent if model persistence fails.
            return .none
        case let .devicePairing(id, pool, previous):
            try pool.removeSavedConnection(for: id)
            guard let previous else { return .none }
            return .restorePairing(id, pool.store, previous)
        }
    }

    @MainActor
    func disconnectAfterPersistence() {
        if case let .devicePairing(id, pool, _) = self {
            Task { await pool.disconnect(id) }
        }
    }

    enum Compensation {
        case none
        case restorePairing(UUID, any TailcatConnectionStoring, TailcatConnection)

        func restoreAfterPersistenceFailure() throws {
            guard case let .restorePairing(id, store, previous) = self else { return }
            do {
                // The device-only pairing contains its password as well.
                try store.setConnection(previous, for: id)
            } catch {
                // Restoration failure takes precedence over the original save error.
                throw TailcatError.pairingRestoreFailed
            }
        }
    }
}
