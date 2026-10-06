import Foundation
import HTTPTypes
import Nexus
import Testing

@testable import Roost

@Suite("ErrorRescue")
struct ErrorRescueTests {

    // MARK: - Helpers

    private func makeConn(accept: String? = nil) -> Connection {
        var fields = HTTPFields()
        if let accept {
            fields[.accept] = accept
        }
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "localhost",
            path: "/test",
            headerFields: fields
        )
        return Connection(request: request)
    }

    // MARK: - NexusHTTPError (JSON)

    @Test func jsonErrorInDev() async throws {
        let plug = roost_rescueErrors { _ in
            throw NexusHTTPError(.notFound, message: "Donut not found")
        }
        let conn = makeConn(accept: "application/json")
        let result = try await plug(conn)

        #expect(result.response.status == .notFound)
        #expect(result.isHalted)
        #expect(result.response.headerFields[.contentType] == "application/json")

        // In dev (default test env), should include message
        if case .buffered(let data) = result.responseBody {
            let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
            #expect(json["error"] == "NexusHTTPError")
            #expect(json["message"] == "Donut not found")
            #expect(json["status"] == "404")
        } else {
            Issue.record("Expected buffered response body")
        }
    }

    @Test func jsonErrorFallsBackToReasonPhrase() async throws {
        let plug = roost_rescueErrors { _ in
            throw NexusHTTPError(.notFound)
        }
        let conn = makeConn(accept: "application/json")
        let result = try await plug(conn)

        if case .buffered(let data) = result.responseBody {
            let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
            #expect(json["message"] == "Not Found")
        } else {
            Issue.record("Expected buffered response body")
        }
    }

    // MARK: - NexusHTTPError (HTML)

    @Test func htmlErrorForBrowser() async throws {
        let plug = roost_rescueErrors { _ in
            throw NexusHTTPError(.notFound, message: "Page not found")
        }
        let conn = makeConn(accept: "text/html")
        let result = try await plug(conn)

        #expect(result.response.status == .notFound)
        #expect(result.isHalted)
        #expect(result.response.headerFields[.contentType] == "text/html; charset=utf-8")

        if case .buffered(let data) = result.responseBody {
            let body = String(data: data, encoding: .utf8)!
            #expect(body.contains("<!DOCTYPE html>"))
            // Dev page should contain debug details
            #expect(body.contains("NexusHTTPError"))
            #expect(body.contains("Page not found"))
            #expect(body.contains("/test"))
        } else {
            Issue.record("Expected buffered response body")
        }
    }

    // MARK: - Content Negotiation

    @Test func defaultsToJSONWhenNoAcceptHeader() async throws {
        let plug = roost_rescueErrors { _ in
            throw NexusHTTPError(.badRequest, message: "bad")
        }
        let conn = makeConn()
        let result = try await plug(conn)

        // No Accept header → prefersHTML is false → JSON
        // But Nexus returns false for prefersHTML, so we get JSON
        #expect(result.response.status == .badRequest)
        #expect(result.isHalted)
    }

    // MARK: - Infrastructure Errors

    @Test func infrastructureErrorReturns500() async throws {
        struct DBError: Error {}

        let plug = roost_rescueErrors { _ in
            throw DBError()
        }
        let conn = makeConn(accept: "application/json")
        let result = try await plug(conn)

        #expect(result.response.status == .internalServerError)
        #expect(result.isHalted)
    }

    // MARK: - Custom Error Page

    @Test func customErrorPageOverridesDefault() async throws {
        let customRenderer: ErrorPageRenderer = { conn, status, message in
            conn.text("Custom: \(status) \(message)", status: .notFound)
        }

        let plug = roost_rescueErrors(
            { _ in throw NexusHTTPError(.notFound, message: "gone") },
            customErrorPage: customRenderer
        )
        let conn = makeConn(accept: "text/html")
        let result = try await plug(conn)

        if case .buffered(let data) = result.responseBody {
            let body = String(data: data, encoding: .utf8)!
            #expect(body == "Custom: 404 gone")
        } else {
            Issue.record("Expected buffered response body")
        }
    }

    @Test func customErrorPageNilFallsBackToDefault() async throws {
        let customRenderer: ErrorPageRenderer = { _, _, _ in nil }

        let plug = roost_rescueErrors(
            { _ in throw NexusHTTPError(.notFound, message: "nope") },
            customErrorPage: customRenderer
        )
        let conn = makeConn(accept: "application/json")
        let result = try await plug(conn)

        // Should fall back to default JSON response
        #expect(result.response.headerFields[.contentType] == "application/json")
    }

    // MARK: - Successful Requests Pass Through

    @Test func noErrorPassesThrough() async throws {
        let plug = roost_rescueErrors { conn in
            conn.text("OK")
        }
        let conn = makeConn()
        let result = try await plug(conn)

        #expect(result.response.status == .ok)
        if case .buffered(let data) = result.responseBody {
            #expect(String(data: data, encoding: .utf8) == "OK")
        }
    }
}
