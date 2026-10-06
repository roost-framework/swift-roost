import Foundation
import NexusTest
import Testing
@testable import Roost

@Suite("View rendering and forms")
struct ViewRenderingTests {
    private struct Page: ESWView {
        var action = "/save"
        var method = "post"
        func render() -> String {
            Form.render(action: action, method: method, content: "<button>Save</button>")
        }
    }

    private struct Fragment: ESWView {
        let content: () -> String
        func render() -> String { content() }
    }

    private func body(_ conn: Connection) -> String {
        if case .buffered(let data) = conn.responseBody { return String(decoding: data, as: UTF8.self) }
        return ""
    }

    @Test func formsUseTheMiddlewareTokenAndValidateOnSubmit() async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        let html = body(try conn.render(Page()))
        #expect(html.contains("name=\"_csrf_token\" value=\"\(conn.csrfToken)\""))
        let post = TestConnection.buildForm(method: .post, path: "/save", form: "_csrf_token=\(conn.csrfToken)")
            .assign(key: Connection.sessionKey, value: conn.session)
        #expect(try await !roost_csrfProtection()(post).isHalted)
        let missing = TestConnection.buildForm(method: .post, path: "/save", form: "")
            .assign(key: Connection.sessionKey, value: conn.session)
        #expect(try await roost_csrfProtection()(missing).response.status == .forbidden)
    }

    @Test(arguments: ["put", "PATCH", "delete"])
    func methodOverride(method: String) async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        let html = body(try conn.render(Page(method: method)))
        #expect(html.contains("method=\"post\""))
        #expect(html.contains("name=\"_method\" value=\"\(method.uppercased())\""))
    }

    @Test func missingMiddlewareFailsInsteadOfRenderingAnUnprotectedForm() throws {
        #expect(throws: ViewRenderingError.self) { try TestConnection.build().render(Page()) }
        #expect(!Page().render().contains("<form"))
    }

    @Test(arguments: ["/search", "https://outside.test/submit", "//outside.test/submit"])
    func getFormsNeverIncludeTokens(action: String) async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        let html = body(try conn.render(Page(action: action, method: "get")))
        #expect(html.contains("<form"))
        #expect(!html.contains("_csrf_token"))
    }

    @Test(arguments: ["https://outside.test/submit", "//outside.test/submit", "http://example.com/save", "https://example.com:444/save"])
    func externalActionsDoNotReceiveTokens(action: String) async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        let html = body(try conn.render(Page(action: action)))
        #expect(html.contains("<form"))
        #expect(!html.contains("_csrf_token"))
    }

    @Test(arguments: ["/save", "save", "?save=1", "https://example.com/save", "https://example.com:443/save", "//example.com/save"])
    func sameOriginActionsReceiveTokens(action: String) async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        #expect(body(try conn.render(Page(action: action))).contains(conn.csrfToken))
    }

    @Test(arguments: ["javascript:alert(1)", "/\\outside.test/save", "\n//outside.test/save", " https://outside.test/save"])
    func invalidActionsAreRejected(action: String) async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        #expect(throws: ViewRenderingError.self) { try conn.render(Page(action: action)) }
    }

    @Test func layoutsStatusAndEscaping() async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        let layout: HTMLLayout = { _, title, content in "<title>\(ESW.escape(title))</title>" + content }
        let rendered = try conn.assign(HTMLLayoutKey.self, value: layout)
            .render(Page(action: "/save?q=\"<tag>"), title: "<Title>", status: .unprocessableContent)
        #expect(rendered.response.status == .unprocessableContent)
        #expect(body(rendered).contains("<title>&lt;Title&gt;</title>"))
        #expect(body(rendered).contains("action=\"/save?q=&quot;&lt;tag&gt;\""))
        #expect(rendered.response.headerFields[.contentType]?.contains("text/html") == true)
    }

    @Test func formAttributesAreEscapedAndCannotOverrideProtection() async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        let html = body(try conn.render(Fragment {
            Form.render(action: "/save", id: "form\"<id>", class: "editor", multipart: true,
                        attributes: ["data-kind": "\"<unsafe>", "novalidate": ""], content: "<button>Save</button>")
        }))
        #expect(html.contains("id=\"form&quot;&lt;id&gt;\""))
        #expect(html.contains("enctype=\"multipart/form-data\""))
        #expect(html.contains("data-kind=\"&quot;&lt;unsafe&gt;\""))
        #expect(html.contains("<button>Save</button>"))
        for name in ["ACTION", "method", "enctype", "data-x\" onclick"] {
            #expect(throws: ViewRenderingError.self) {
                try conn.render(Fragment { Form.render(action: "/save", attributes: [name: "unsafe"]) })
            }
        }
        #expect(throws: ViewRenderingError.self) { try conn.render(Page(method: "invalid")) }
    }

    @Test func nestedRenderingRestoresTheOuterScopeAfterErrors() async throws {
        let conn = try await roost_csrfProtection()(TestConnection.build())
        let inner = TestConnection.build()
        let html = body(try conn.render(Fragment {
            #expect(throws: ViewRenderingError.self) { try inner.render(Page()) }
            return Page().render()
        }))
        #expect(html.contains(conn.csrfToken))
        #expect(FormRenderContext.current == nil)
        #expect(body(try inner.render(Page(method: "get"))).contains("<form"))
    }

    @Test func concurrentRequestsKeepTheirOwnTokens() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let token = "token-\(index)-unique"
                    let conn = TestConnection.build().assign(key: Connection.sessionKey, value: ["_csrf_token": token])
                    let prepared = try await roost_csrfProtection()(conn)
                    let html = body(try prepared.render(Page()))
                    #expect(html.contains("value=\"\(token)\""))
                    #expect(html.components(separatedBy: "name=\"_csrf_token\"").count == 2)
                }
            }
            try await group.waitForAll()
        }
        #expect(FormRenderContext.current == nil)
    }
}
