import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

@Suite("Live Reload")
struct LiveReloadTests {

    private func send(
        _ env: Environment,
        method: HTTPRequest.Method = .get,
        path: String = "/",
        _ respond: @escaping @Sendable (Connection) -> Connection
    ) async throws -> Connection {
        let plug = Roost.$environmentOverride.withValue(env) {
            roost_liveReload { conn in respond(conn) }
        }
        return try await plug(TestConnection.build(method: method, path: path))
    }

    private func body(_ conn: Connection) -> String {
        guard case .buffered(let data) = conn.responseBody else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Script injection

    @Test("Injects the script before </body> of HTML in dev")
    func injectsBeforeBody() async throws {
        let conn = try await send(.dev) { $0.html("<html><body><p>Hi</p></BODY></html>") }
        let html = body(conn)

        #expect(html.hasPrefix("<html><body><p>Hi</p><script>"))
        #expect(html.hasSuffix("</script></BODY></html>"))
        #expect(html.contains(liveReloadPath))
    }

    @Test("Appends the script to HTML without </body>")
    func appendsWithoutBody() async throws {
        let conn = try await send(.dev) { $0.html("<p>Fragment</p>") }

        #expect(body(conn).hasPrefix("<p>Fragment</p><script>"))
        #expect(body(conn).hasSuffix("</script>"))
    }

    @Test("Leaves JSON, text, and encoded HTML unchanged")
    func skipsOtherResponses() async throws {
        let json = try await send(.dev) { $0.respond(status: .ok, body: .string(#"{"a":1}"#)).putRespHeader(.contentType, "application/json") }
        let text = try await send(.dev) { $0.text("</body>") }
        let encoded = try await send(.dev) { $0.html("<body></body>").putRespHeader(.contentEncoding, "gzip") }

        #expect(body(json) == #"{"a":1}"#)
        #expect(body(text) == "</body>")
        #expect(body(encoded) == "<body></body>")
    }

    @Test("Leaves HEAD responses unchanged")
    func skipsHead() async throws {
        let conn = try await send(.dev, method: .head) { $0.html("<body></body>") }
        #expect(body(conn) == "<body></body>")
    }

    @Test("Does nothing outside dev", arguments: [Environment.test, .prod])
    func offOutsideDev(env: Environment) async throws {
        let page = try await send(env) { $0.html("<body></body>") }
        let endpoint = try await send(env, path: liveReloadPath) { $0.text("app") }

        #expect(body(page) == "<body></body>")
        #expect(body(endpoint) == "app")
    }

    @Test("Streams the boot ID first from the endpoint in dev")
    func servesEndpoint() async throws {
        let conn = try await send(.dev, path: liveReloadPath) { $0.text("app") }
        guard case .stream(let stream) = conn.responseBody else {
            Issue.record("Expected a streaming body")
            return
        }
        var events = stream.makeAsyncIterator()
        let first = try #require(try await events.next().flatMap(ServerSentEvent.parse))

        #expect(conn.response.headerFields[.contentType] == "text/event-stream")
        #expect(first.event == "boot")
        #expect(first.data == LiveReloadHub.shared.bootID)
    }

    @Test("Creates the shutdown signal sources once and cancels them with the hub")
    func shutdownSignalSources() async throws {
        var hub: LiveReloadHub? = LiveReloadHub(directory: NSTemporaryDirectory() + "missing-\(UUID().uuidString)")
        // A browser that disconnects and reconnects subscribes twice.
        _ = await hub?.subscribe()
        _ = await hub?.subscribe()
        let sources = hub?.shutdownSignals ?? []
        #expect(sources.count == 2)

        // The dropped streams unsubscribe asynchronously before the hub is released.
        hub = nil
        let deadline = ContinuousClock.now + .seconds(2)
        while !sources.allSatisfy({ $0.isCancelled }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(sources.allSatisfy { $0.isCancelled })
    }

    // MARK: - CSS change detection

    @Test("Reports a stylesheet whose modification time changed and ignores other files")
    func detectsCSSChanges() throws {
        let dir = NSTemporaryDirectory() + "roost-live-reload-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/css", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for file in ["css/app.css", "css/other.css", "app.js", "index.html"] {
            try "x".write(toFile: dir + "/" + file, atomically: true, encoding: .utf8)
        }
        var detector = CSSChangeDetector(directory: dir)
        #expect(detector.changes().isEmpty)

        let later = Date().addingTimeInterval(60)
        for file in ["css/app.css", "app.js", "index.html"] {
            try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: dir + "/" + file)
        }
        #expect(detector.changes() == ["css/app.css"])
        #expect(detector.changes().isEmpty)

        try "x".write(toFile: dir + "/new.css", atomically: true, encoding: .utf8)
        #expect(detector.changes() == ["new.css"])
    }
}
