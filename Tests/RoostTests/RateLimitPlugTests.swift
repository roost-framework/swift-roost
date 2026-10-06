import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

// MARK: - Helpers

private func buildConn(
    method: HTTPRequest.Method = .get,
    headers: [String: String] = [:],
    assigns: [String: String] = [:]
) -> Connection {
    var conn = TestConnection.build()
    conn.request.method = method
    for (name, value) in headers {
        if let fieldName = HTTPField.Name(name) {
            conn.request.headerFields[fieldName] = value
        }
    }
    for (key, value) in assigns {
        conn.assigns[key] = value
    }
    return conn
}

private func runRateLimitPlug(_ conn: Connection, plug: @escaping Plug) async throws -> Connection {
    try await plug(conn)
}

// MARK: - Tests

@Suite("Rate Limiting")
struct RateLimitPlugTests {

    // MARK: - Basic enforcement

    @Test("returns 429 when limit is exceeded")
    func returns429WhenExceeded() async throws {
        let plug = rateLimit(max: 2, windowSeconds: 60, by: .ip)

        let conn1 = buildConn(headers: ["X-Forwarded-For": "10.0.0.1"])
        let result1 = try await runRateLimitPlug(conn1, plug: plug)
        #expect(!result1.isHalted)

        let conn2 = buildConn(headers: ["X-Forwarded-For": "10.0.0.1"])
        let result2 = try await runRateLimitPlug(conn2, plug: plug)
        #expect(!result2.isHalted)

        let conn3 = buildConn(headers: ["X-Forwarded-For": "10.0.0.1"])
        let result3 = try await runRateLimitPlug(conn3, plug: plug)
        #expect(result3.response.status == .tooManyRequests)
        #expect(result3.isHalted)
    }

    // MARK: - Rate limit headers

    @Test("sets X-RateLimit-Limit, X-RateLimit-Remaining, and X-RateLimit-Reset on all responses")
    func setsRateLimitHeaders() async throws {
        let plug = rateLimit(max: 10, windowSeconds: 60, by: .ip)

        let conn = buildConn(headers: ["X-Forwarded-For": "192.168.1.1"])
        let result = try await runRateLimitPlug(conn, plug: plug)

        #expect(result.response.headerFields[.rateLimitLimitName] == "10")
        #expect(result.response.headerFields[.rateLimitRemainingName] == "9")
        #expect(result.response.headerFields[.rateLimitResetName] != nil)
    }

    // MARK: - Retry-After header

    @Test("sets Retry-After on 429 responses")
    func setsRetryAfter() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 30, by: .ip)

        let conn1 = buildConn(headers: ["X-Forwarded-For": "172.16.0.1"])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(headers: ["X-Forwarded-For": "172.16.0.1"])
        let result = try await runRateLimitPlug(conn2, plug: plug)

        #expect(result.response.headerFields[.retryAfterName] != nil)
    }

    // MARK: - IP key extraction

    @Test("extracts IP from X-Forwarded-For")
    func extractsIPFromForwardedFor() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60)

        let conn = buildConn(headers: ["X-Forwarded-For": "10.0.0.1"])
        let result = try await runRateLimitPlug(conn, plug: plug)

        #expect(!result.isHalted)
        #expect(result.response.headerFields[.rateLimitRemainingName] == "0")
    }

    @Test("extracts IP from X-Real-IP when no X-Forwarded-For")
    func extractsIPFromRealIP() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60)

        let conn = buildConn(headers: ["X-Real-IP": "10.0.0.2"])
        let result = try await runRateLimitPlug(conn, plug: plug)

        #expect(!result.isHalted)
        #expect(result.response.headerFields[.rateLimitRemainingName] == "0")
    }

    @Test("X-Forwarded-For takes priority over X-Real-IP")
    func forwardedForPriority() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60)

        let conn1 = buildConn(
            headers: ["X-Forwarded-For": "10.0.0.1", "X-Real-IP": "10.0.0.2"]
        )
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(
            headers: ["X-Forwarded-For": "10.0.0.1", "X-Real-IP": "10.0.0.2"]
        )
        let result2 = try await runRateLimitPlug(conn2, plug: plug)
        #expect(result2.response.status == .tooManyRequests)

        let conn3 = buildConn(
            headers: ["X-Forwarded-For": "10.0.0.3", "X-Real-IP": "10.0.0.2"]
        )
        let result3 = try await runRateLimitPlug(conn3, plug: plug)
        #expect(!result3.isHalted)
    }

    @Test("different IPs are tracked separately")
    func differentIPs() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60)

        let conn1 = buildConn(headers: ["X-Forwarded-For": "10.0.0.1"])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(headers: ["X-Forwarded-For": "10.0.0.2"])
        let result2 = try await runRateLimitPlug(conn2, plug: plug)
        #expect(!result2.isHalted)
    }

    // MARK: - Header key

    @Test("header key uses specified request header")
    func headerKey() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60, by: .header(.authorization))

        let conn1 = buildConn(headers: ["Authorization": "Bearer abc123"])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(headers: ["Authorization": "Bearer abc123"])
        let result2 = try await runRateLimitPlug(conn2, plug: plug)
        #expect(result2.response.status == .tooManyRequests)

        let conn3 = buildConn(headers: ["Authorization": "Bearer xyz789"])
        let result3 = try await runRateLimitPlug(conn3, plug: plug)
        #expect(!result3.isHalted)
    }

    // MARK: - Assign key

    @Test("assign key uses connection assigns")
    func assignKey() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60, by: .assign("user_id"))

        let conn1 = buildConn(assigns: ["user_id": "42"])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(assigns: ["user_id": "42"])
        let result2 = try await runRateLimitPlug(conn2, plug: plug)
        #expect(result2.response.status == .tooManyRequests)

        let conn3 = buildConn(assigns: ["user_id": "99"])
        let result3 = try await runRateLimitPlug(conn3, plug: plug)
        #expect(!result3.isHalted)
    }

    // MARK: - Custom key

    @Test("custom key allows arbitrary extraction")
    func customKey() async throws {
        let plug = rateLimit(
            max: 1,
            windowSeconds: 60,
            by: .custom { conn in
                conn.request.headerFields[.xAPIKeyName]
            }
        )

        let conn1 = buildConn(headers: ["X-API-Key": "key-1"])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(headers: ["X-API-Key": "key-1"])
        let result2 = try await runRateLimitPlug(conn2, plug: plug)
        #expect(result2.response.status == .tooManyRequests)
    }

    @Test("nil from custom key passes through without limiting")
    func nilCustomKey() async throws {
        let plug = rateLimit(
            max: 1,
            windowSeconds: 60,
            by: .custom { _ in nil }
        )

        for _ in 0..<10 {
            let result = try await runRateLimitPlug(buildConn(), plug: plug)
            #expect(!result.isHalted)
            #expect(result.response.status != .tooManyRequests)
        }
    }

    // MARK: - Content negotiation

    @Test("429 returns JSON for JSON requests")
    func json429() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60, by: .ip)

        let conn1 = buildConn(method: .post, headers: [
            "X-Forwarded-For": "10.0.0.5",
            "Content-Type": "application/json",
        ])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(method: .post, headers: [
            "X-Forwarded-For": "10.0.0.5",
            "Content-Type": "application/json",
            "Accept": "application/json",
        ])
        let result = try await runRateLimitPlug(conn2, plug: plug)
        #expect(result.response.headerFields[.contentType] == "application/json")
        if case .buffered(let data) = result.responseBody {
            let json = String(data: data, encoding: .utf8)
            #expect(json?.contains("error") == true)
        } else {
            Issue.record("Expected buffered body")
        }
    }

    @Test("429 returns plain text for non-JSON requests")
    func plainText429() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60, by: .ip)

        let conn1 = buildConn(headers: ["X-Forwarded-For": "10.0.0.99"])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(headers: ["X-Forwarded-For": "10.0.0.99"])
        let result = try await runRateLimitPlug(conn2, plug: plug)
        #expect(result.response.headerFields[.contentType] == nil)
        if case .buffered(let data) = result.responseBody {
            #expect(String(data: data, encoding: .utf8) == "Too Many Requests")
        } else {
            Issue.record("Expected buffered body")
        }
    }

    // MARK: - Custom 429 message

    @Test("custom message appears in 429 response")
    func customMessage() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60, message: "Slow down!")

        let conn1 = buildConn(headers: ["X-Forwarded-For": "10.0.0.50"])
        _ = try await runRateLimitPlug(conn1, plug: plug)

        let conn2 = buildConn(headers: ["X-Forwarded-For": "10.0.0.50"])
        let result = try await runRateLimitPlug(conn2, plug: plug)
        if case .buffered(let data) = result.responseBody {
            #expect(String(data: data, encoding: .utf8) == "Slow down!")
        } else {
            Issue.record("Expected buffered body")
        }
    }

    // MARK: - Multiple plugs coexist

    @Test("multiple rate limit plugs can coexist")
    func multiplePlugs() async throws {
        let globalPlug = rateLimit(max: 100, windowSeconds: 60, by: .ip)
        let strictPlug = rateLimit(max: 2, windowSeconds: 60, by: .ip)

        // Request 1: both plugs allow
        let conn1 = buildConn(headers: ["X-Forwarded-For": "192.168.2.1"])
        let result1 = try await runRateLimitPlug(conn1, plug: globalPlug)
        let result1s = try await runRateLimitPlug(result1, plug: strictPlug)
        #expect(!result1s.isHalted)

        // Request 2: strict at 2/2, still allowed
        let conn2 = buildConn(headers: ["X-Forwarded-For": "192.168.2.1"])
        let result2 = try await runRateLimitPlug(conn2, plug: globalPlug)
        let result2s = try await runRateLimitPlug(result2, plug: strictPlug)
        #expect(!result2s.isHalted)

        // Request 3: strict should hit 429
        let conn3 = buildConn(headers: ["X-Forwarded-For": "192.168.2.1"])
        _ = try await runRateLimitPlug(conn3, plug: globalPlug)
        let result3 = try await runRateLimitPlug(conn3, plug: strictPlug)
        #expect(result3.response.status == .tooManyRequests)
    }

    // MARK: - IP with multiple proxies

    @Test("X-Forwarded-For takes first IP in comma-separated list")
    func forwardedForMultipleIPs() async throws {
        let plug = rateLimit(max: 1, windowSeconds: 60)

        let conn = buildConn(headers: ["X-Forwarded-For": "1.2.3.4, 5.6.7.8, 9.10.11.12"])
        let result = try await runRateLimitPlug(conn, plug: plug)

        #expect(result.response.headerFields[.rateLimitLimitName] == "1")
        #expect(result.response.headerFields[.rateLimitRemainingName] == "0")
    }
}

// MARK: - Test header name

extension HTTPField.Name {
    static let xAPIKeyName = Self("X-API-Key")!
}
