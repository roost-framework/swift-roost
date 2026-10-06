import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

// MARK: - Helpers

private func buildConn(
    method: HTTPRequest.Method = .get,
    headers: [String: String] = [:]
) -> Connection {
    var conn = TestConnection.build()
    conn.request.method = method
    conn.request.url = URL(string: "http://localhost/test")
    for (key, value) in headers {
        if let name = HTTPField.Name(key) {
            conn.request.headerFields[name] = value
        }
    }
    // Provide a Host header for proper redirect URL construction
    if conn.request.headerFields[HTTPField.Name("Host")!] == nil {
        conn.request.headerFields[HTTPField.Name("Host")!] = "example.com"
    }
    return conn
}

private func runPlug(_ conn: Connection, plug: Plug) async throws -> Connection {
    try await plug(conn)
}

@Suite("HTTPS Redirect Plug")
struct HTTPSRedirectPlugTests {

    @Test("redirects when X-Forwarded-Proto is http")
    func redirectsWhenProtoIsHTTP() async throws {
        let plug = httpsRedirect()
        let conn = buildConn(headers: [
            "X-Forwarded-Proto": "http",
            "X-Forwarded-Host": "example.com"
        ])

        let result = try await runPlug(conn, plug: plug)

        #expect(result.isHalted)
        #expect(result.response.status == .permanentRedirect)
        let location = result.response.headerFields[.location]
        #expect(location?.hasPrefix("https://") == true)
    }

    @Test("redirects when X-Forwarded-Proto is missing")
    func redirectsWhenProtoMissing() async throws {
        let plug = httpsRedirect()
        let conn = buildConn()

        let result = try await runPlug(conn, plug: plug)

        #expect(result.isHalted)
        #expect(result.response.status == .permanentRedirect)
    }

    @Test("passes through when X-Forwarded-Proto is https")
    func passesThroughWhenSecure() async throws {
        let plug = httpsRedirect()
        let conn = buildConn(headers: ["X-Forwarded-Proto": "https"])

        let result = try await runPlug(conn, plug: plug)

        #expect(!result.isHalted)
    }

    @Test("passes through when X-Forwarded-SSL is on")
    func passesThroughWhenSSLOn() async throws {
        let plug = httpsRedirect()
        let conn = buildConn(headers: ["X-Forwarded-SSL": "on"])

        let result = try await runPlug(conn, plug: plug)

        #expect(!result.isHalted)
    }

    @Test("redirects when X-Forwarded-SSL is off")
    func redirectsWhenSSLOff() async throws {
        let plug = httpsRedirect()
        let conn = buildConn(headers: ["X-Forwarded-SSL": "off"])

        let result = try await runPlug(conn, plug: plug)

        #expect(result.isHalted)
        #expect(result.response.status == .permanentRedirect)
    }

    @Test("includes original path and query in redirect URL")
    func preservesPathAndQuery() async throws {
        let plug = httpsRedirect()
        var conn = buildConn(headers: ["X-Forwarded-Proto": "http"])
        conn.request.url = URL(string: "http://example.com/api/users?page=1")

        let result = try await runPlug(conn, plug: plug)

        let location = result.response.headerFields[.location]
        #expect(location == "https://example.com/api/users?page=1")
    }

    @Test("uses localhost when no Host header")
    func usesLocalhostFallback() async throws {
        let plug = httpsRedirect()
        var conn = TestConnection.build()
        conn.request.method = .get
        conn.request.url = URL(string: "http://localhost/test")
        // No Host header set

        let result = try await runPlug(conn, plug: plug)

        let location = result.response.headerFields[.location]
        #expect(location == "https://localhost/test")
    }

    @Test("X-Forwarded-Proto case insensitivity")
    func protoCaseInsensitive() async throws {
        let plug = httpsRedirect()
        let conn = buildConn(headers: ["X-Forwarded-Proto": "HTTPS"])

        let result = try await runPlug(conn, plug: plug)

        #expect(!result.isHalted)
    }

    @Test("X-Forwarded-SSL case insensitivity")
    func sslCaseInsensitive() async throws {
        let plug = httpsRedirect()
        let conn = buildConn(headers: ["X-Forwarded-SSL": "ON"])

        let result = try await runPlug(conn, plug: plug)

        #expect(!result.isHalted)
    }
}
