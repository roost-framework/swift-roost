import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

// MARK: - Helpers

/// Runs a connection through the CORS plug and returns the result.
private func runCORSPlug(_ conn: Connection, plug: Plug) async throws -> Connection {
    try await plug(conn)
}

/// Creates a GET request with an Origin header.
private func buildConnWithOrigin(
    _ origin: String? = nil,
    method: HTTPRequest.Method = .get
) -> Connection {
    var conn = TestConnection.build()
    conn.request.method = method
    if let origin {
        conn.request.headerFields[.origin] = origin
    }
    return conn
}

// MARK: - Tests

@Suite("CORS")
struct CORSPlugTests {

    // MARK: - Preflight OPTIONS returns 204 with correct headers

    @Test("preflight OPTIONS returns 204 with all CORS headers")
    func preflightReturns204() async throws {
        let plug = cors(
            allowOrigin: .exact("https://myapp.com"),
            allowMethods: [.get, .post],
            allowHeaders: [.contentType, .authorization],
            maxAge: 3600,
            allowCredentials: true
        )

        let conn = buildConnWithOrigin("https://myapp.com", method: .options)
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.status == .noContent)
        #expect(result.response.headerFields[.accessControlAllowOrigin] == "https://myapp.com")
        #expect(result.response.headerFields[.allow] == "GET, POST")
        #expect(result.response.headerFields[.allowHeadersName] == "Content-Type, Authorization")
        #expect(result.response.headerFields[.maxAgeName] == "3600")
        #expect(result.response.headerFields[.credentialsName] == "true")
        #expect(result.isHalted)
    }

    // MARK: - .originBased reflects request origin

    @Test(".originBased reflects the request's Origin header")
    func originBasedReflectsRequestOrigin() async throws {
        let plug = cors(allowOrigin: .originBased)

        let conn = buildConnWithOrigin("https://random.example.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.accessControlAllowOrigin] == "https://random.example.com")
        #expect(!result.isHalted)
    }

    // MARK: - .exact only allows specified origin

    @Test(".exact allows only the configured origin")
    func exactAllowsOnlyConfiguredOrigin() async throws {
        let plug = cors(allowOrigin: .exact("https://myapp.com"))

        let conn = buildConnWithOrigin("https://myapp.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.accessControlAllowOrigin] == "https://myapp.com")
        #expect(!result.isHalted)
    }

    @Test(".exact rejects other origins with 403")
    func exactRejectsOtherOrigins() async throws {
        let plug = cors(allowOrigin: .exact("https://myapp.com"))

        let conn = buildConnWithOrigin("https://evil.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.status == .forbidden)
        #expect(result.isHalted)
    }

    // MARK: - .allowList accepts multiple origins

    @Test(".allowList accepts any of the configured origins")
    func allowListAcceptsConfiguredOrigins() async throws {
        let plug = cors(allowOrigin: .allowList(["https://a.com", "https://b.com"]))

        let conn = buildConnWithOrigin("https://b.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.accessControlAllowOrigin] == "https://b.com")
        #expect(!result.isHalted)
    }

    @Test(".allowList rejects unconfigured origins")
    func allowListRejectsOthers() async throws {
        let plug = cors(allowOrigin: .allowList(["https://a.com", "https://b.com"]))

        let conn = buildConnWithOrigin("https://c.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.status == .forbidden)
    }

    // MARK: - .any sets wildcard

    @Test(".any sets wildcard origin")
    func anySetsWildcard() async throws {
        let plug = cors(allowOrigin: .any)

        let conn = buildConnWithOrigin("https://anything.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.accessControlAllowOrigin] == "*")
        #expect(!result.isHalted)
    }

    @Test("preflight with .any sets wildcard")
    func preflightWithAny() async throws {
        let plug = cors(allowOrigin: .any)

        let conn = buildConnWithOrigin("https://anything.com", method: .options)
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.accessControlAllowOrigin] == "*")
        #expect(result.response.status == .noContent)
    }

    // MARK: - allowCredentials

    @Test("allowCredentials sets Access-Control-Allow-Credentials")
    func allowCredentials() async throws {
        let plug = cors(allowOrigin: .exact("https://myapp.com"), allowCredentials: true)

        let conn = buildConnWithOrigin("https://myapp.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.credentialsName] == "true")
    }

    @Test("preflight with credentials sets Allow-Credentials header")
    func preflightWithCredentials() async throws {
        let plug = cors(allowOrigin: .exact("https://myapp.com"), allowCredentials: true)

        let conn = buildConnWithOrigin("https://myapp.com", method: .options)
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.credentialsName] == "true")
    }

    // MARK: - exposeHeaders

    @Test("exposeHeaders sets Access-Control-Expose-Headers")
    func exposeHeaders() async throws {
        let plug = cors(
            allowOrigin: .exact("https://myapp.com"),
            exposeHeaders: [.contentType, HTTPField.Name("X-Custom")!]
        )

        let conn = buildConnWithOrigin("https://myapp.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.exposeHeadersName] == "Content-Type, X-Custom")
    }

    @Test("empty exposeHeaders does not set header")
    func emptyExposeHeaders() async throws {
        let plug = cors(allowOrigin: .exact("https://myapp.com"))

        let conn = buildConnWithOrigin("https://myapp.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.exposeHeadersName] == nil)
    }

    // MARK: - No Origin header

    @Test("requests without Origin header pass through unmodified")
    func noOriginPassesThrough() async throws {
        let plug = cors(allowOrigin: .exact("https://myapp.com"))

        let conn = buildConnWithOrigin(nil)
        let result = try await runCORSPlug(conn, plug: plug)

        // Response should be unchanged — no CORS headers set
        #expect(result.response.headerFields[.accessControlAllowOrigin] == nil)
        #expect(result.response.headerFields[.credentialsName] == nil)
    }

    // MARK: - Custom origin validation

    @Test("custom validator allows matching domain suffix")
    func customValidator() async throws {
        let plug = cors(allowOrigin: .custom { origin in
            origin.hasSuffix(".example.com")
        })

        let conn = buildConnWithOrigin("https://app.example.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.accessControlAllowOrigin] == "https://app.example.com")
    }

    @Test("custom validator rejects non-matching domain")
    func customValidatorRejects() async throws {
        let plug = cors(allowOrigin: .custom { origin in
            origin.hasSuffix(".example.com")
        })

        let conn = buildConnWithOrigin("https://evil.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.status == .forbidden)
    }

    // MARK: - Preflight halts pipeline

    @Test("preflight OPTIONS halts the connection")
    func preflightHaltsPipeline() async throws {
        let plug = cors(allowOrigin: .originBased)

        let conn = buildConnWithOrigin("https://any.com", method: .options)
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.isHalted)
        #expect(result.response.status == .noContent)
    }

    // MARK: - Actual request continues pipeline

    @Test("actual request does not halt pipeline")
    func actualRequestContinues() async throws {
        let plug = cors(allowOrigin: .exact("https://myapp.com"))

        let conn = buildConnWithOrigin("https://myapp.com")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(!result.isHalted)
    }

    // MARK: - Default values

    @Test("cors() with no arguments uses originBased default")
    func defaultsUseOriginBased() async throws {
        let plug = cors()

        let conn = buildConnWithOrigin("https://dev.local")
        let result = try await runCORSPlug(conn, plug: plug)

        #expect(result.response.headerFields[.accessControlAllowOrigin] == "https://dev.local")
    }
}
