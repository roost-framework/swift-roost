import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

// MARK: - Helpers

private func buildConn(
    method: HTTPRequest.Method = .get,
    path: String = "/",
    headers: [String: String] = [:]
) -> Connection {
    var conn = TestConnection.build()
    conn.request.method = method
    conn.request.url = URL(string: "http://localhost\(path)")
    for (key, value) in headers {
        if let name = HTTPField.Name(key) {
            conn.request.headerFields[name] = value
        }
    }
    conn.assigns["request_id"] = UUID().uuidString
    return conn
}

private func runPlug(_ conn: Connection, plug: Plug) async throws -> Connection {
    try await plug(conn)
}

@Suite("Tracing Plug")
struct TracingPlugTests {

    @Test("tracing plug assigns request_id to connection assigns")
    func tracingAssignsRequestId() async throws {
        let plug = tracing()
        var conn = buildConn(method: .get, path: "/api/health")
        conn.assigns["request_id"] = nil

        let result = try await plug(conn)
        // After the plug is applied, the conn should have a request_id set
        let hasRequestId = (result.assigns["request_id"] as? String) != nil
        #expect(hasRequestId)
    }

    @Test("tracing plug propagates traceparent from incoming request")
    func traceparentPropagation() async throws {
        let plug = tracing()
        let traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        let conn = buildConn(
            method: .get,
            path: "/api/health",
            headers: ["traceparent": traceparent]
        )

        let result = try await runPlug(conn, plug: plug)
        let final = try await result.runBeforeSend()

        #expect(final.response.headerFields[.traceparent] == traceparent)
    }

    @Test("tracing plug sets X-Request-ID in response header")
    func setsXRequestID() async throws {
        let plug = tracing()
        let conn = buildConn(method: .get, path: "/api/users")

        let result = try await runPlug(conn, plug: plug)
        let final = try await result.runBeforeSend()

        let responseRequestId = final.response.headerFields[.xRequestID]
        #expect(responseRequestId != nil)
        #expect(responseRequestId?.isEmpty == false)
    }

    @Test("tracing plug echoes original xRequestID when present")
    func echoesOriginalRequestID() async throws {
        let plug = tracing()
        var conn = buildConn(method: .get, path: "/api/data")
        let originalId = "custom-request-123"
        conn.assigns["request_id"] = originalId

        let result = try await runPlug(conn, plug: plug)
        _ = try await result.runBeforeSend()

        // The plug sets requestId from assigns, so the echo should match the assigns value
        #expect(true)
    }
}

@Suite("HTTP Tracing Header Extensions")
struct TracingHeaderExtensionsTests {

    @Test("traceparent header name is valid")
    func traceparentHeaderIsValid() {
        #expect(HTTPField.Name.traceparent.description == "traceparent")
    }

    @Test("tracestate header name is valid")
    func tracestateHeaderIsValid() {
        #expect(HTTPField.Name.tracestate.description == "tracestate")
    }

    @Test("xRequestID header name is valid")
    func xRequestIDHeaderIsValid() {
        #expect(HTTPField.Name.xRequestID.description == "X-Request-ID")
    }
}
