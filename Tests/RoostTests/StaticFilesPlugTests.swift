import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

@Suite("Static File Serving")
struct StaticFilesPlugTests {

    /// Temporary directory populated with test files for each test instance.
    let tempDir: String

    init() throws {
        let tmp =
            NSTemporaryDirectory()
            + "roost-static-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmp,
            withIntermediateDirectories: true
        )

        // Root-level files
        try "body { color: red; }".write(
            toFile: tmp + "/style.css",
            atomically: true,
            encoding: .utf8
        )
        try "console.log('hi')".write(
            toFile: tmp + "/app.js",
            atomically: true,
            encoding: .utf8
        )
        try "<html></html>".write(
            toFile: tmp + "/index.html",
            atomically: true,
            encoding: .utf8
        )

        // Subdirectory
        try FileManager.default.createDirectory(
            atPath: tmp + "/css",
            withIntermediateDirectories: true
        )
        try "h1 { font-size: 2rem; }".write(
            toFile: tmp + "/css/main.css",
            atomically: true,
            encoding: .utf8
        )

        // Hidden file (should never be served)
        try "SECRET=bad".write(
            toFile: tmp + "/.env",
            atomically: true,
            encoding: .utf8
        )

        // Hidden directory
        try FileManager.default.createDirectory(
            atPath: tmp + "/.secret",
            withIntermediateDirectories: true
        )
        try "hidden".write(
            toFile: tmp + "/.secret/data.txt",
            atomically: true,
            encoding: .utf8
        )

        // Fingerprinted asset (for cache header testing)
        try "fingerprinted".write(
            toFile: tmp + "/app-3a7f2b1c.js",
            atomically: true,
            encoding: .utf8
        )

        // A nested directory without files (for directory request test)
        try FileManager.default.createDirectory(
            atPath: tmp + "/empty",
            withIntermediateDirectories: true
        )

        tempDir = tmp
    }

    // MARK: - Basic Serving

    @Test func servesExistingCSSFile() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/style.css")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
        #expect(
            result.response.headerFields[.contentType] == "text/css; charset=utf-8"
        )
    }

    @Test func servesFileRequestedWithQueryString() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/css/main.css?v=2")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
    }

    @Test func servesExistingJSFile() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/app.js")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
        #expect(
            result.response.headerFields[.contentType]
                == "application/javascript; charset=utf-8"
        )
    }

    @Test func servesHTMLFile() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/index.html")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
        #expect(
            result.response.headerFields[.contentType]
                == "text/html; charset=utf-8"
        )
    }

    @Test func servesSubdirectoryFile() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/css/main.css")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
        #expect(
            result.response.headerFields[.contentType] == "text/css; charset=utf-8"
        )
    }

    // MARK: - Pass-through Behavior

    @Test func nonExistentFilePassesThrough() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/missing.css")
        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test func postRequestsPassThrough() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .post, path: "/style.css")
        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test func putRequestsPassThrough() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .put, path: "/style.css")
        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test func directoryRequestPassesThrough() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/css")
        let result = try await plug(conn)

        // Directories should not be served — pass through to router
        #expect(!result.isHalted)
    }

    @Test func emptyDirectoryRequestPassesThrough() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/empty")
        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test func rootRequestPassesThrough() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/")
        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    // MARK: - Security

    @Test func pathTraversalRejected() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(
            method: .get, path: "/../../../etc/passwd"
        )
        let result = try await plug(conn)

        #expect(result.response.status == .badRequest)
        #expect(result.isHalted)
    }

    @Test func hiddenFilesNotServed() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/.env")
        let result = try await plug(conn)

        #expect(result.response.status == .notFound)
        #expect(result.isHalted)
    }

    @Test func hiddenDirectoryNotServed() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(
            method: .get, path: "/.secret/data.txt"
        )
        let result = try await plug(conn)

        #expect(result.response.status == .notFound)
        #expect(result.isHalted)
    }

    @Test func nullByteRejected() async throws {
        let plug = roost_staticFiles(from: tempDir)
        // Use percent-encoded null byte (%00); the HTTP layer normalises raw \0
        // before it reaches the plug, so %00 is the form that must be rejected.
        let conn = TestConnection.build(
            method: .get, path: "/style%00.css"
        )
        let result = try await plug(conn)

        #expect(result.response.status == .badRequest)
        #expect(result.isHalted)
    }

    // MARK: - MIME Types

    @Test func unknownExtensionGetsOctetStream() async throws {
        // Create a file with an uncommon extension
        try "data".write(
            toFile: tempDir + "/file.xyz",
            atomically: true,
            encoding: .utf8
        )
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/file.xyz")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(
            result.response.headerFields[.contentType] == "application/octet-stream"
        )
    }

    // MARK: - Cache Headers

    @Test func devModeSetsNoCacheHeader() async throws {
        // Roost.env defaults to .dev in test environment
        // (ROOST_ENV is not set during tests)
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .get, path: "/style.css")
        let result = try await plug(conn)

        #expect(result.isHalted)
        let cache = result.response.headerFields[.cacheControl]
        #expect(cache == "no-cache")
    }

    // MARK: - HEAD Requests

    @Test func headRequestReturnsHeadersWithEmptyBody() async throws {
        let plug = roost_staticFiles(from: tempDir)
        let conn = TestConnection.build(method: .head, path: "/style.css")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
        // Content type header should still be present
        #expect(
            result.response.headerFields[.contentType] == "text/css; charset=utf-8"
        )
        // Body should be empty for HEAD requests
        switch result.responseBody {
        case .empty:
            break  // expected
        default:
            Issue.record("HEAD response body should be .empty")
        }
    }

    // MARK: - Custom Prefix

    @Test func customPrefixServesFiles() async throws {
        let plug = roost_staticFiles(from: tempDir, at: "/assets")
        let conn = TestConnection.build(method: .get, path: "/assets/style.css")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
    }

    @Test func customPrefixIgnoresNonMatchingPaths() async throws {
        let plug = roost_staticFiles(from: tempDir, at: "/assets")
        let conn = TestConnection.build(method: .get, path: "/style.css")
        let result = try await plug(conn)

        #expect(!result.isHalted)
    }

    @Test func customPrefixWithTrailingSlash() async throws {
        let plug = roost_staticFiles(from: tempDir, at: "/assets/")
        let conn = TestConnection.build(method: .get, path: "/assets/style.css")
        let result = try await plug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
    }
}
