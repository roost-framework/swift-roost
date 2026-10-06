import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

@Suite("CSRF Protection")
struct CSRFPlugTests {

    // MARK: - Helpers

    /// Builds a connection with an optional pre-populated session.
    private func makeConn(
        method: HTTPRequest.Method = .get,
        path: String = "/",
        headers: HTTPFields = [:],
        session: [String: String] = [:]
    ) -> Connection {
        var conn = TestConnection.build(method: method, path: path, headers: headers)
        if !session.isEmpty {
            conn = conn.assign(key: Connection.sessionKey, value: session)
        }
        return conn
    }

    /// Builds a form POST connection with body params and optional session.
    private func makeFormPost(
        path: String = "/",
        form: String,
        session: [String: String] = [:]
    ) -> Connection {
        var conn = TestConnection.buildForm(method: .post, path: path, form: form)
        if !session.isEmpty {
            conn = conn.assign(key: Connection.sessionKey, value: session)
        }
        return conn
    }

    // MARK: - GET Requests

    @Test("GET request generates a CSRF token and stores it in assigns")
    func getRequestGeneratesToken() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .get)
        let result = try await plug(conn)

        let token = result.assigns["csrfToken"] as? String
        #expect(token != nil)
        #expect(!token!.isEmpty)
    }

    @Test("GET request stores token in session for later validation")
    func getRequestStoresTokenInSession() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .get)
        let result = try await plug(conn)

        let sessionToken = result.getSession("_csrf_token")
        let assignToken = result.assigns["csrfToken"] as? String
        #expect(sessionToken != nil)
        #expect(sessionToken == assignToken)
    }

    @Test("HEAD request skips CSRF validation")
    func headRequestSkips() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .head)
        let result = try await plug(conn)

        #expect(!result.isHalted)
        let token = result.assigns["csrfToken"] as? String
        #expect(token != nil)
    }

    @Test("OPTIONS request skips CSRF validation")
    func optionsRequestSkips() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .options)
        let result = try await plug(conn)

        #expect(!result.isHalted)
        let token = result.assigns["csrfToken"] as? String
        #expect(token != nil)
    }

    // MARK: - POST Validation

    @Test("POST without token returns 403 Forbidden")
    func postWithoutTokenReturns403() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .post)
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    @Test("POST with valid token in _csrf_token form field passes validation")
    func postWithFormTokenPasses() async throws {
        let plug = roost_csrfProtection()
        let token = "test-csrf-token-abc123"
        let conn = makeFormPost(
            form: "_csrf_token=\(token)",
            session: ["_csrf_token": token]
        )

        let result = try await plug(conn)

        #expect(!result.isHalted)
        #expect(result.response.status != .forbidden)
    }

    @Test("POST with valid token in x-csrf-token header passes validation")
    func postWithHeaderTokenPasses() async throws {
        let plug = roost_csrfProtection()
        let token = "test-csrf-token-header"
        var headers = HTTPFields()
        if let headerName = HTTPField.Name("x-csrf-token") {
            headers[headerName] = token
        }
        let conn = makeConn(
            method: .post,
            headers: headers,
            session: ["_csrf_token": token]
        )

        let result = try await plug(conn)

        #expect(!result.isHalted)
        #expect(result.response.status != .forbidden)
    }

    @Test("POST with invalid token returns 403")
    func postWithInvalidTokenReturns403() async throws {
        let plug = roost_csrfProtection()
        let conn = makeFormPost(
            form: "_csrf_token=wrong-token",
            session: ["_csrf_token": "correct-token"]
        )

        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    @Test("POST with empty session token returns 403")
    func postWithEmptySessionTokenReturns403() async throws {
        let plug = roost_csrfProtection()
        let conn = makeFormPost(
            form: "_csrf_token=some-token",
            session: ["_csrf_token": ""]
        )

        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    // MARK: - PUT / PATCH / DELETE

    @Test("PUT without token returns 403")
    func putWithoutTokenReturns403() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .put)
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    @Test("PATCH without token returns 403")
    func patchWithoutTokenReturns403() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .patch)
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    @Test("DELETE without token returns 403")
    func deleteWithoutTokenReturns403() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .delete)
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    // MARK: - JSON Skipping

    @Test("JSON POST request skips CSRF validation")
    func jsonPostSkipsCSRF() async throws {
        let plug = roost_csrfProtection(skipJSON: true)
        let conn = TestConnection.buildJSON(
            method: .post,
            path: "/api/data",
            json: "{\"key\": \"value\"}"
        )

        let result = try await plug(conn)

        #expect(!result.isHalted)
        #expect(result.response.status != .forbidden)
    }

    @Test("JSON PUT request skips CSRF validation")
    func jsonPutSkipsCSRF() async throws {
        let plug = roost_csrfProtection(skipJSON: true)
        let conn = TestConnection.buildJSON(
            method: .put,
            path: "/api/data",
            json: "{}"
        )

        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test("JSON DELETE request skips CSRF validation")
    func jsonDeleteSkipsCSRF() async throws {
        let plug = roost_csrfProtection(skipJSON: true)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let conn = makeConn(method: .delete, headers: headers)

        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test("JSON content type with charset skips CSRF validation")
    func jsonWithCharsetSkipsCSRF() async throws {
        let plug = roost_csrfProtection(skipJSON: true)
        var headers = HTTPFields()
        headers[.contentType] = "application/json; charset=utf-8"
        let conn = makeConn(method: .post, headers: headers)

        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test("Non-JSON POST does not skip CSRF validation")
    func nonJsonPostDoesNotSkip() async throws {
        let plug = roost_csrfProtection()
        var headers = HTTPFields()
        headers[.contentType] = "text/html"
        let conn = makeConn(method: .post, headers: headers)

        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    // MARK: - Path Exclusions

    @Test("Excluded path skips CSRF validation on POST")
    func excludedPathSkipsCSRF() async throws {
        let plug = roost_csrfProtection(except: ["/webhooks/stripe"])
        let conn = makeConn(method: .post, path: "/webhooks/stripe")

        let result = try await plug(conn)

        #expect(!result.isHalted)
        #expect(result.response.status != .forbidden)
    }

    @Test("Excluded path still injects token assigns")
    func excludedPathInjectsAssigns() async throws {
        let plug = roost_csrfProtection(except: ["/webhooks/stripe"])
        let conn = makeConn(method: .post, path: "/webhooks/stripe")

        let result = try await plug(conn)

        let token = result.assigns["csrfToken"] as? String
        #expect(token != nil)
        #expect(!token!.isEmpty)
    }

    @Test("Non-excluded path still validates CSRF on POST")
    func nonExcludedPathValidates() async throws {
        let plug = roost_csrfProtection(except: ["/webhooks/stripe"])
        let conn = makeConn(method: .post, path: "/submit")

        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .forbidden)
    }

    @Test("Multiple excluded paths all skip validation")
    func multipleExcludedPaths() async throws {
        let plug = roost_csrfProtection(except: [
            "/webhooks/stripe",
            "/webhooks/github",
            "/api/health",
        ])

        for path in ["/webhooks/stripe", "/webhooks/github", "/api/health"] {
            let conn = makeConn(method: .post, path: path)
            let result = try await plug(conn)
            #expect(!result.isHalted, "Expected \(path) to skip CSRF validation")
        }
    }

    // MARK: - Template Assigns

    @Test("csrfToken assign contains the token string")
    func csrfTokenAssignPresent() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .get)
        let result = try await plug(conn)

        let token = result.assigns["csrfToken"] as? String
        #expect(token != nil)
        #expect(!token!.isEmpty)
    }

    @Test("csrfTag assign produces correct hidden input HTML")
    func csrfTagAssignProducesHTML() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .get)
        let result = try await plug(conn)

        let tag = result.assigns["csrfTag"] as? String
        let token = result.assigns["csrfToken"] as? String
        #expect(tag != nil)
        #expect(token != nil)

        let expectedTag = "<input type=\"hidden\" name=\"_csrf_token\" value=\"\(token!)\">"
        #expect(tag == expectedTag)
    }

    @Test("csrfTag contains the same token as csrfToken assign")
    func csrfTagMatchesToken() async throws {
        let plug = roost_csrfProtection()
        let conn = makeConn(method: .get)
        let result = try await plug(conn)

        let tag = result.assigns["csrfTag"] as? String ?? ""
        let token = result.assigns["csrfToken"] as? String ?? ""

        #expect(tag.contains(token))
        #expect(tag.contains("name=\"_csrf_token\""))
        #expect(tag.contains("type=\"hidden\""))
    }

    // MARK: - Token Stability

    @Test("Existing session token is reused, not regenerated")
    func existingTokenReused() async throws {
        let plug = roost_csrfProtection()
        let existingToken = "my-existing-token-xyz"
        let conn = makeConn(
            method: .get,
            session: ["_csrf_token": existingToken]
        )

        let result = try await plug(conn)

        let token = result.assigns["csrfToken"] as? String
        #expect(token == existingToken)
    }

    @Test("Valid POST with form token injects assigns on success")
    func validPostInjectsAssigns() async throws {
        let plug = roost_csrfProtection()
        let token = "valid-token-for-assigns"
        let conn = makeFormPost(
            form: "_csrf_token=\(token)",
            session: ["_csrf_token": token]
        )

        let result = try await plug(conn)

        #expect(!result.isHalted)
        let assignedToken = result.assigns["csrfToken"] as? String
        #expect(assignedToken == token)

        let tag = result.assigns["csrfTag"] as? String
        #expect(tag != nil)
        #expect(tag!.contains(token))
    }
}
