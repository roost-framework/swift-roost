import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

// MARK: - Helpers

/// Runs a connection through the flash plug and executes beforeSend callbacks,
/// simulating a complete request lifecycle.
private func runFlashPlug(_ conn: Connection) async throws -> Connection {
    let plug = flashPlug()
    let result = try await plug(conn)
    return result.runBeforeSend()
}

/// Creates a connection with session data pre-populated, as if the session
/// plug had already run.
private func buildConnWithSession(_ session: [String: String]) -> Connection {
    var conn = TestConnection.build()
    conn = conn.assign(key: Connection.sessionKey, value: session)
    return conn
}

/// Encodes a dictionary as the JSON string stored in the `_flash` session key.
private func encodeFlashSession(_ dict: [String: String]) -> String {
    let data = try! JSONEncoder().encode(dict)
    return String(data: data, encoding: .utf8)!
}

// MARK: - Tests

@Suite("Flash Messages")
struct FlashPlugTests {

    // MARK: - putFlash stores messages for next request

    @Test("putFlash stores message that is available on the next request")
    func putFlashStoresForNextRequest() async throws {
        // Request 1: set a flash message via putFlash
        let conn1 = buildConnWithSession([:])
        let plug = flashPlug()
        let afterPlug = try await plug(conn1)

        // Route handler sets a flash
        let afterHandler = afterPlug.putFlash(.info, "Item created")

        // beforeSend writes pending flash to session
        let sent = afterHandler.runBeforeSend()

        // Verify the flash was written to session
        let sessionFlash = sent.getSession("_flash")
        #expect(sessionFlash != nil)

        // Request 2: the flash should be readable
        let session2 = sent.assigns[Connection.sessionKey] as? [String: String] ?? [:]
        let conn2 = buildConnWithSession(session2)
        let result2 = try await plug(conn2)

        #expect(result2.flash.info == "Item created")
        #expect(result2[FlashKey.self]?.info == "Item created")
    }

    // MARK: - Flash is available after reading

    @Test("flash message is populated in assigns after flashPlug reads session")
    func flashAvailableAfterReading() async throws {
        let flashData = encodeFlashSession(["info": "Welcome back"])
        let conn = buildConnWithSession(["_flash": flashData])

        let plug = flashPlug()
        let result = try await plug(conn)

        // Typed access
        #expect(result[FlashKey.self]?.info == "Welcome back")
        #expect(result.flash.info == "Welcome back")

        // String-keyed access for templates
        let templateFlash = result.assigns["flash"] as? Flash
        #expect(templateFlash?.info == "Welcome back")
    }

    // MARK: - Flash is cleared after being read (displays exactly once)

    @Test("flash is cleared from session after reading — displays exactly once")
    func flashClearedAfterRead() async throws {
        let flashData = encodeFlashSession(["error": "Something went wrong"])
        let conn = buildConnWithSession(["_flash": flashData, "user_id": "42"])

        let plug = flashPlug()
        let afterPlug = try await plug(conn)

        // Flash is available on this request
        #expect(afterPlug.flash.error == "Something went wrong")

        // Run beforeSend (no pending flash was set, so nothing new is written)
        let sent = afterPlug.runBeforeSend()

        // The _flash key should have been removed from session
        let session = sent.assigns[Connection.sessionKey] as? [String: String] ?? [:]
        #expect(session["_flash"] == nil)
        // Other session keys should still be present
        #expect(session["user_id"] == "42")

        // Request 3: simulate the next request with the cleaned session
        let conn3 = buildConnWithSession(session)
        let result3 = try await plug(conn3)

        #expect(result3.flash.isEmpty)
        #expect(result3.flash.error == nil)
    }

    // MARK: - Multiple flash levels coexist

    @Test("multiple flash levels can coexist in a single flash")
    func multipleFlashLevels() async throws {
        let flashData = encodeFlashSession([
            "info": "Saved",
            "warning": "Profile incomplete",
            "error": "Payment failed",
        ])
        let conn = buildConnWithSession(["_flash": flashData])

        let plug = flashPlug()
        let result = try await plug(conn)

        #expect(result.flash.info == "Saved")
        #expect(result.flash.warning == "Profile incomplete")
        #expect(result.flash.error == "Payment failed")
        #expect(!result.flash.isEmpty)
    }

    // MARK: - putFlash same level: last write wins

    @Test("putFlash called multiple times for the same level — last write wins")
    func putFlashLastWriteWins() async throws {
        let conn = buildConnWithSession([:])

        let plug = flashPlug()
        let afterPlug = try await plug(conn)

        // Call putFlash multiple times for the same level
        let step1 = afterPlug.putFlash(.info, "First message")
        let step2 = step1.putFlash(.info, "Second message")
        let step3 = step2.putFlash(.info, "Final message")

        let sent = step3.runBeforeSend()

        // Verify the session has the last message
        let sessionFlash = sent.getSession("_flash")
        #expect(sessionFlash != nil)

        let data = sessionFlash!.data(using: .utf8)!
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        #expect(dict["info"] == "Final message")
    }

    // MARK: - Flash is empty when no messages were set

    @Test("flash is empty when no messages were set on the previous request")
    func flashEmptyWhenNoMessages() async throws {
        let conn = buildConnWithSession([:])

        let plug = flashPlug()
        let result = try await plug(conn)

        #expect(result.flash.isEmpty)
        #expect(result.flash.info == nil)
        #expect(result.flash.error == nil)
        #expect(result.flash.warning == nil)
    }

    // MARK: - No-op when no session data exists

    @Test("flash plug is a no-op when no session data exists")
    func flashPlugNoOpWithoutSession() async throws {
        // Build a plain connection with no session data at all
        let conn = TestConnection.build()

        let plug = flashPlug()
        let result = try await plug(conn)

        #expect(result.flash.isEmpty)

        // beforeSend should not write _flash to session when nothing is pending
        let sent = result.runBeforeSend()
        let sessionFlash = sent.getSession("_flash")
        #expect(sessionFlash == nil)
    }

    // MARK: - putFlash across different levels

    @Test("putFlash can set different levels independently")
    func putFlashDifferentLevels() async throws {
        let conn = buildConnWithSession([:])

        let plug = flashPlug()
        let afterPlug = try await plug(conn)

        let updated = afterPlug
            .putFlash(.info, "Created")
            .putFlash(.warning, "Slow connection")

        let sent = updated.runBeforeSend()

        let sessionFlash = sent.getSession("_flash")
        #expect(sessionFlash != nil)

        let data = sessionFlash!.data(using: .utf8)!
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        #expect(dict["info"] == "Created")
        #expect(dict["warning"] == "Slow connection")
        #expect(dict["error"] == nil)
    }

    // MARK: - Full two-request cycle

    @Test("complete two-request flash cycle: set on request 1, read on request 2, gone on request 3")
    func fullTwoRequestCycle() async throws {
        let plug = flashPlug()

        // --- Request 1: handler sets a flash ---
        let conn1 = buildConnWithSession([:])
        let afterPlug1 = try await plug(conn1)

        // No flash to read yet
        #expect(afterPlug1.flash.isEmpty)

        // Handler sets flash
        let afterHandler1 = afterPlug1.putFlash(.info, "Account created")
        let sent1 = afterHandler1.runBeforeSend()

        // Extract session state for next request
        let session1 = sent1.assigns[Connection.sessionKey] as? [String: String] ?? [:]
        #expect(session1["_flash"] != nil)

        // --- Request 2: flash is readable, then cleared ---
        let conn2 = buildConnWithSession(session1)
        let afterPlug2 = try await plug(conn2)

        #expect(afterPlug2.flash.info == "Account created")

        // No new flash set by handler
        let sent2 = afterPlug2.runBeforeSend()
        let session2 = sent2.assigns[Connection.sessionKey] as? [String: String] ?? [:]

        // _flash should be gone
        #expect(session2["_flash"] == nil)

        // --- Request 3: flash is empty ---
        let conn3 = buildConnWithSession(session2)
        let afterPlug3 = try await plug(conn3)

        #expect(afterPlug3.flash.isEmpty)
    }
}
