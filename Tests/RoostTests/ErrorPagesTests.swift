import HTTPTypes
import Nexus
import Testing

@testable import Roost

@Suite("ErrorPages")
struct ErrorPagesTests {

    private func makeConn() -> Connection {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "localhost:8080",
            path: "/api/donuts/42",
            headerFields: HTTPFields([
                HTTPField(name: .accept, value: "text/html"),
                HTTPField(name: .userAgent, value: "TestBrowser/1.0"),
            ])
        )
        return Connection(request: request)
            .assign(key: "user_id", value: "abc123")
    }

    // MARK: - Dev Page

    @Test func devPageIncludesErrorType() {
        let html = devErrorPageHTML(
            status: 404,
            errorType: "NexusHTTPError",
            message: "Donut not found",
            conn: makeConn()
        )
        #expect(html.contains("NexusHTTPError"))
    }

    @Test func devPageIncludesMessage() {
        let html = devErrorPageHTML(
            status: 500,
            errorType: "DBError",
            message: "Connection refused",
            conn: makeConn()
        )
        #expect(html.contains("Connection refused"))
    }

    @Test func devPageIncludesRequestInfo() {
        let html = devErrorPageHTML(
            status: 404,
            errorType: "NexusHTTPError",
            message: "not found",
            conn: makeConn()
        )
        #expect(html.contains("GET"))
        #expect(html.contains("/api/donuts/42"))
    }

    @Test func devPageIncludesHeaders() {
        let html = devErrorPageHTML(
            status: 404,
            errorType: "NexusHTTPError",
            message: "not found",
            conn: makeConn()
        )
        #expect(html.contains("TestBrowser/1.0"))
    }

    @Test func devPageIncludesAssigns() {
        let html = devErrorPageHTML(
            status: 500,
            errorType: "Error",
            message: "oops",
            conn: makeConn()
        )
        #expect(html.contains("user_id"))
        #expect(html.contains("abc123"))
    }

    @Test func devPageShowsEmptyAssigns() {
        let conn = Connection(request: HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "localhost",
            path: "/",
            headerFields: HTTPFields()
        ))
        let html = devErrorPageHTML(
            status: 500,
            errorType: "Error",
            message: "oops",
            conn: conn
        )
        #expect(html.contains("No assigns"))
    }

    @Test func devPageEscapesHTML() {
        let html = devErrorPageHTML(
            status: 500,
            errorType: "Error",
            message: "<script>alert('xss')</script>",
            conn: makeConn()
        )
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    // MARK: - Prod Page

    @Test func prodPageShowsStatusAndReason() {
        let html = prodErrorPageHTML(status: 404, reason: "Not Found")
        #expect(html.contains("404"))
        #expect(html.contains("Not Found"))
    }

    @Test func prodPageIsMinimal() {
        let html = prodErrorPageHTML(status: 500, reason: "Internal Server Error")
        // Should NOT contain debug info
        #expect(!html.contains("assigns"))
        #expect(!html.contains("Headers"))
        #expect(!html.contains("monospace"))
    }

    @Test func prodPageEscapesHTML() {
        let html = prodErrorPageHTML(status: 500, reason: "<img onerror=alert(1)>")
        #expect(!html.contains("<img"))
        #expect(html.contains("&lt;img"))
    }

    // MARK: - Reason Phrases

    @Test func commonReasonPhrases() {
        #expect(reasonPhrase(for: 400) == "Bad Request")
        #expect(reasonPhrase(for: 401) == "Unauthorized")
        #expect(reasonPhrase(for: 403) == "Forbidden")
        #expect(reasonPhrase(for: 404) == "Not Found")
        #expect(reasonPhrase(for: 500) == "Internal Server Error")
        #expect(reasonPhrase(for: 503) == "Service Unavailable")
    }

    @Test func unknownStatusFallsBackToError() {
        #expect(reasonPhrase(for: 418) == "Error")
        #expect(reasonPhrase(for: 999) == "Error")
    }
}
