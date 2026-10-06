import Foundation
import Nexus
import Crypto

// MARK: - Session Key

/// Typed assign key for the session store injected by the session plug.
public enum RoostSessionKey: AssignKey {
    public typealias Value = any SessionStore
}

package enum TestSessionSeedKey: AssignKey {
    package typealias Value = [String: String]
}

// MARK: - Session ID cookie

/// Default session cookie name.
public let defaultSessionCookie = "_roost_session"
/// Default session TTL (24 hours).
public let defaultSessionTTL: Duration = .seconds(24 * 3600)

// MARK: - Secure Random ID Generator

/// Generates a URL-safe, cryptographically random session identifier.
private func generateSessionID() -> String {
    Auth.generateToken()
}

// MARK: - SessionPendingOps

/// Persistence work for the request's current session data.
struct SessionPendingOps: Sendable {
    var isModified = false
    var clearAll = false
    var renewToNewID: String?
    var renewOldID: String?
}

// MARK: - SessionPlug

/// A plug that initializes session management via a ``SessionStore`` backend.
///
/// The plug loads session data on the way in. Session mutations in plugs
/// and route handlers are immediately visible on the returned connection.
/// RoostApp and TestApp await persistence when the request pipeline
/// completes, before running response hooks and sending the response.
///
/// When using this plug outside RoostApp or TestApp, await
/// ``Nexus/Connection/flushSession()`` before calling `runBeforeSend()`.
public func session(
    store: SessionStore,
    cookieName: String = defaultSessionCookie,
    ttl: Duration = defaultSessionTTL
) -> Plug {
    { conn in
        // A nested browser pipeline must not reload and discard session writes.
        guard conn[RoostSessionKey.self] == nil else { return conn }
        var result = conn

        // Inject the store and configuration into assigns
        result = result.assign(SessionCookieNameKey.self, value: cookieName)
        result = result.assign(RoostSessionKey.self, value: store)
        result = result.assign(SessionTTLKey.self, value: ttl)
        result = result.assign(SessionPendingOpsKey.self, value: SessionPendingOps())
        result = result.assign(SessionDataKey.self, value: [:])

        // Extract session ID from cookie or generate new one
        let existingSessID = conn.reqCookies[cookieName]
        var sessionID: String

        if existingSessID != nil && !existingSessID!.isEmpty {
            sessionID = existingSessID!

            // Load session data from store
            if let data = try await store.get(sessionID) {
                result = result.assign(SessionDataKey.self, value: data)
            }
        } else {
            sessionID = generateSessionID()
            // Mark that we need to set the Set-Cookie header
            result = result.assign(NewSessionIDKey.self, value: sessionID)
        }

        // Nexus owns the string session view used by CSRF, flash and its public
        // session helpers. Keep non-string values in Roost's typed storage.
        let data = result[SessionDataKey.self] ?? [:]
        let strings = data.compactMapValues { $0 as? String }
        result = result.assign(key: Connection.sessionKey, value: strings)
        result = result.assign(SessionInitialStringsKey.self, value: strings)

        // Track session ID
        result = result.assign(SessionIDKey.self, value: sessionID)

        // Response hooks only emit cookies. Store I/O is awaited by the pipeline.
        result = result.registerBeforeSend { c in
            guard c[SessionCookieSuppressedKey.self] != true else { return c }
            var conn = c
            let ops = conn[SessionPendingOpsKey.self] ?? SessionPendingOps()
            let cookie: String
            if ops.clearAll {
                cookie = "\(cookieName)=deleted; Path=/; HttpOnly; Max-Age=0"
            } else if let newID = ops.renewToNewID ?? conn[NewSessionIDKey.self] {
                cookie = "\(cookieName)=\(newID); Path=/; HttpOnly; SameSite=Lax"
            } else {
                return conn
            }
            conn.response.headerFields.append(HTTPField(name: .setCookie, value: cookie))
            return conn
        }

        if let seed = conn[TestSessionSeedKey.self] {
            for (key, value) in seed { result = result.putSessionValue(key, value) }
        }
        return result
    }
}

// MARK: - Session Assign Keys

private enum SessionCookieNameKey: AssignKey {
    typealias Value = String
}

private enum SessionTTLKey: AssignKey {
    typealias Value = Duration
}

private enum SessionIDKey: AssignKey {
    typealias Value = String
}

private enum NewSessionIDKey: AssignKey {
    typealias Value = String
}

enum SessionDataKey: AssignKey {
    typealias Value = [String: any Sendable]
}

private enum SessionInitialStringsKey: AssignKey {
    typealias Value = [String: String]
}

private enum SessionPendingOpsKey: AssignKey {
    typealias Value = SessionPendingOps
}

private enum SessionCookieSuppressedKey: AssignKey {
    typealias Value = Bool
}

// MARK: - Connection Extensions — session helpers

extension Connection {

    /// Retrieves a value from the server-side session store.
    public func sessionValue(_ key: String) -> (any Sendable)? {
        if let string = getSession(key) { return string }
        let value = self[SessionDataKey.self]?[key]
        // A deleted Nexus string must not reappear from the original snapshot.
        return value is String && assigns[Connection.sessionKey] != nil ? nil : value
    }

    /// Updates a session value and queues it for persistence.
    public func putSessionValue(_ key: String, _ value: some Sendable) -> Connection {
        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.isModified = true
        var data = self[SessionDataKey.self] ?? [:]
        data[key] = value
        let conn = assign(SessionPendingOpsKey.self, value: ops)
            .assign(SessionDataKey.self, value: data)
        if let string = value as? String { return conn.putSession(key: key, value: string) }
        return conn.deleteSession(key)
    }

    /// Queues removal of a key from the session store.
    public func deleteSessionValue(_ key: String) -> Connection {
        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.isModified = true
        var data = self[SessionDataKey.self] ?? [:]
        data.removeValue(forKey: key)
        return assign(SessionPendingOpsKey.self, value: ops)
            .assign(SessionDataKey.self, value: data)
            .deleteSession(key)
    }

    /// Queues the session to be cleared and its cookie removed.
    public func clearSessionID() -> Connection {
        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.clearAll = true
        return assign(SessionPendingOpsKey.self, value: ops)
            .assign(SessionDataKey.self, value: [:])
            .clearSession()
    }

    /// Generates a new session ID while preserving current session data.
    public func renewSessionID() -> Connection {
        let oldID = self[SessionIDKey.self]
        let newID = generateSessionID()

        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.renewToNewID = newID
        ops.renewOldID = ops.renewOldID ?? oldID

        return assign(SessionIDKey.self, value: newID)
            .assign(SessionPendingOpsKey.self, value: ops)
    }

    /// Flushes all pending session writes to the store immediately.
    /// RoostApp and TestApp await this before response hooks run.
    public func flushSession() async throws {
        guard let sessionID = self[SessionIDKey.self],
              let store = self[RoostSessionKey.self],
              let ttl = self[SessionTTLKey.self]
        else { return }

        let ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        let strings = assigns[Connection.sessionKey] as? [String: String] ?? [:]
        var data = (self[SessionDataKey.self] ?? [:]).filter { !($0.value is String) }
        for (key, value) in strings { data[key] = value }

        if ops.clearAll {
            try await store.delete(sessionID)
            if let oldID = ops.renewOldID, oldID != sessionID {
                try await store.delete(oldID)
            }
            return
        }

        if let renewID = ops.renewToNewID {
            if let oldID = ops.renewOldID, oldID != renewID {
                try await store.delete(oldID)
            }
            try await store.set(renewID, data: data, ttl: ttl)
            return
        }
        if ops.isModified || strings != self[SessionInitialStringsKey.self] ?? [:] {
            try await store.set(sessionID, data: data, ttl: ttl)
        }
    }

    /// Do not advertise a session change if its persistence failed.
    func suppressSessionCookie() -> Connection {
        assign(SessionCookieSuppressedKey.self, value: true)
    }
}
