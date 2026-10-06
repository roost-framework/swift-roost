import Foundation
import HTTPTypes
import Nexus

// MARK: - RateLimitKey

/// How to identify clients for rate limiting.
public enum RateLimitKey: Sendable {
    /// Client IP address from `X-Forwarded-For` / `X-Real-IP` / socket.
    case ip
    /// A specific request header value (e.g. API key).
    case header(HTTPField.Name)
    /// A value from connection assigns (e.g. user ID after auth).
    case assign(String)
    /// Custom extraction function. Return nil to skip rate limiting.
    case custom(@Sendable (Connection) -> String?)
}

// MARK: - Rate Limit Result

private struct RateLimitResult {
    let allowed: Bool
    let limit: Int
    let remaining: Int
    let resetDate: Date
}

// MARK: - Sliding Window Store (per-plug instance)

private actor RateLimitStore {
    struct WindowEntry {
        var count: Int
        var windowStart: Date
    }

    private var entries: [String: WindowEntry] = [:]

    func check(key: String, maxRequests: Int, windowSeconds: Int, now: Date) -> RateLimitResult {
        let window = TimeInterval(windowSeconds)
        if var entry = entries[key] {
            if now >= entry.windowStart.addingTimeInterval(window) {
                entry = WindowEntry(count: 1, windowStart: now)
                entries[key] = entry
            } else {
                entry.count += 1
                entries[key] = entry
            }
            let resetDate = entry.windowStart.addingTimeInterval(window)
            let remaining = Swift.max(0, maxRequests - entry.count)
            return RateLimitResult(
                allowed: entry.count <= maxRequests,
                limit: maxRequests,
                remaining: remaining,
                resetDate: resetDate
            )
        } else {
            entries[key] = WindowEntry(count: 1, windowStart: now)
            return RateLimitResult(
                allowed: true,
                limit: maxRequests,
                remaining: maxRequests - 1,
                resetDate: now.addingTimeInterval(window)
            )
        }
    }

    func cleanup(olderThan: Date) {
        entries = entries.filter { _, entry in
            entry.windowStart >= olderThan
        }
    }
}

// MARK: - Background cleanup

/// Cleans up expired entries across all plug stores every 60 seconds.
private final class RateLimitCleanup: @unchecked Sendable {
    static let shared = RateLimitCleanup()
    private let lock = NSLock()
    private var stores: [ObjectIdentifier: RateLimitStore] = [:]

    func register(_ id: ObjectIdentifier, store: RateLimitStore) {
        lock.withLock { stores[id] = store }
    }

    private init() {
        Task.detached(priority: .background) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                    let cutoff = Date.now.addingTimeInterval(-3600)
                    let stores = self.lock.withLock { Array(self.stores.values) }
                    for store in stores {
                        await store.cleanup(olderThan: cutoff)
                    }
                } catch {
                    break
                }
            }
        }
    }
}

// Start cleanup at module load.
private let rateLimitCleanup = RateLimitCleanup.shared

// MARK: - Rate Limit Plug

/// A plug that limits the number of requests per client within a sliding time window.
///
/// Uses an in-memory store with automatic cleanup of expired entries.
///
/// ```swift
/// // Global rate limit
/// var plugs: [Plug] {
///     [rateLimit(max: 100, windowSeconds: 60), requestLogger()]
/// }
/// ```
///
/// - Parameters:
///   - max: Maximum number of requests allowed per window.
///   - windowSeconds: Duration of the sliding window in seconds.
///   - by: How to identify the client. Defaults to IP address.
///   - message: Custom error message for 429 responses.
/// - Returns: A plug that enforces rate limits and sets `X-RateLimit-*` headers.
public func rateLimit(
    max: Int,
    windowSeconds: Int,
    by: RateLimitKey = .ip,
    message: String = "Too Many Requests"
) -> Plug {
    let store = RateLimitStore()
    let id = ObjectIdentifier(store)
    rateLimitCleanup.register(id, store: store)

    return { conn in
        let clientKey = extractKey(from: conn, using: by)
        guard let clientKey else { return conn }

        let now = Date.now
        let limitResult = await store.check(
            key: clientKey,
            maxRequests: max,
            windowSeconds: windowSeconds,
            now: now
        )

        var updated = conn
        updated.response.headerFields[.rateLimitLimitName] = String(limitResult.limit)
        updated.response.headerFields[.rateLimitRemainingName] = String(limitResult.remaining)
        let resetInterval = limitResult.resetDate.timeIntervalSince1970
        updated.response.headerFields[.rateLimitResetName] = String(Int(resetInterval))

        guard limitResult.allowed else {
            let secondsUntilReset = Int(ceil(limitResult.resetDate.timeIntervalSince(now)))
            updated.response.status = .tooManyRequests
            updated.response.headerFields[.retryAfterName] = String(secondsUntilReset)

            if requestsJSON(conn) {
                updated.response.headerFields[.contentType] = "application/json"
                let body = #"{"error": "\#(message)"}"#
                updated.responseBody = .string(body)
            } else {
                updated.responseBody = .string(message)
            }
            updated.isHalted = true
            return updated
        }

        return updated
    }
}

// MARK: - Key extraction

private func extractKey(from conn: Connection, using key: RateLimitKey) -> String? {
    switch key {
    case .ip:
        if let forwarded = conn.request.headerFields[.xForwardedForName],
           let first = forwarded.split(separator: ",").first {
            return String(first.trimmingCharacters(in: .whitespaces))
        }
        if let realIP = conn.request.headerFields[.xRealIPName] {
            return realIP
        }
        return nil
    case .header(let name):
        return conn.request.headerFields[name]
    case .assign(let name):
        return conn.assigns[name] as? String
    case .custom(let fn):
        return fn(conn)
    }
}

// MARK: - Helpers

private func requestsJSON(_ conn: Connection) -> Bool {
    if let accept = conn.request.headerFields[.accept],
       accept.contains("application/json") {
        return true
    }
    if let contentType = conn.request.headerFields[.contentType],
       contentType.contains("application/json") {
        return true
    }
    return false
}

// MARK: - Non-standard header names

extension HTTPField.Name {
    static let xForwardedForName = Self("X-Forwarded-For")!
    static let xRealIPName = Self("X-Real-IP")!
    static let rateLimitLimitName = Self("X-RateLimit-Limit")!
    static let rateLimitRemainingName = Self("X-RateLimit-Remaining")!
    static let rateLimitResetName = Self("X-RateLimit-Reset")!
    static let retryAfterName = Self("Retry-After")!
}
