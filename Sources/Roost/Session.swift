import Foundation

// MARK: - SessionStore

/// Protocol for session storage backends.
public protocol SessionStore: Sendable {
    /// Retrieves session data for the given session ID.
    /// Returns `nil` when no session exists.
    func get(_ id: String) async throws -> [String: any Sendable]?

    /// Persists session data for the given session ID.
    /// `ttl` controls how long the session remains valid before expiring.
    func set(_ id: String, data: [String: any Sendable], ttl: Duration?) async throws

    /// Deletes the session for the given ID.
    func delete(_ id: String) async throws
}

// MARK: - MemorySessionStore

/// In-memory session store with TTL support — suitable for development and testing.
public actor MemorySessionStore: SessionStore {
    private var sessions: [
        String: (data: [String: any Sendable], expiresAt: ContinuousClock.Instant?)
    ] = [:]
    private let cleanupInterval: Duration

    /// Creates a new in-memory session store.
    /// - Parameter cleanupInterval: How often expired sessions are purged. Defaults to 60 seconds.
    public init(cleanupInterval: Duration = .seconds(60)) {
        self.cleanupInterval = cleanupInterval
    }

    public func get(_ id: String) async throws -> [String: any Sendable]? {
        guard let entry = sessions[id] else { return nil }
        if let expiresAt = entry.expiresAt, ContinuousClock.now >= expiresAt {
            sessions.removeValue(forKey: id)
            return nil
        }
        return entry.data
    }

    public func set(
        _ id: String,
        data: [String: any Sendable],
        ttl: Duration?
    ) async throws {
        let expiresAt: ContinuousClock.Instant? = ttl.map { ContinuousClock.now.advanced(by: $0) }
        sessions[id] = (data: data, expiresAt: expiresAt)
    }

    public func delete(_ id: String) async throws {
        sessions.removeValue(forKey: id)
    }

    /// Removes all expired sessions. Call periodically in production.
    public func cleanup() {
        let now = ContinuousClock.now
        sessions = sessions.filter { _, entry in
            if let expiresAt = entry.expiresAt, now >= expiresAt {
                return false
            }
            return true
        }
    }
}
