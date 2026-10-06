import Testing
import RoostTest
@testable import ChatApp

/// Integration specs for Roost.Channel (Phoenix Channel wire protocol over WebSocket).
///
/// RoostTest provides a `TestChannel` helper that speaks the Phoenix wire
/// protocol in-process — no browser or WebSocket server required.
@Suite("Channel Integration Specs")
struct ChannelIntegrationSpecs {

    // MARK: - Join

    @Suite("Join")
    struct Join {

        @Test("Client can join a topic and receives ok reply")
        func joinSucceeds() async throws {
            let app = try await TestApp(ChatApp.self)
            let socket = try await app.connectSocket("/socket")

            let reply = try await socket.join("room:lobby", payload: [:])

            #expect(reply.status == "ok")
            #expect(reply.payload["room"] as? String == "room:lobby")
        }

        @Test("Unauthenticated client is rejected with error reply")
        func unauthenticatedJoinFails() async throws {
            let app  = try await TestApp(ChatApp.self)
            // No token → socket assigns will have no userID
            let socket = try await app.connectSocket("/socket")

            do {
                _ = try await socket.join("room:lobby", payload: [:])
                Issue.record("Expected join to throw ChannelError.unauthorized")
            } catch let error as ChannelError {
                #expect(error == .unauthorized("Must be authenticated"))
            }
        }

        @Test("Client receives existing presence list on join")
        func receivesPresenceOnJoin() async throws {
            let app = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Alice"])
            let alice = try await app.connectSocket("/socket")
            _ = try await alice.join("room:lobby", payload: [:])

            let app2  = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Bob"])
            let bob   = try await app2.connectSocket("/socket")
            let reply = try await bob.join("room:lobby", payload: [:])

            // Bob should receive current presence state which includes Alice
            #expect(reply.status == "ok")
        }
    }

    // MARK: - Messaging

    @Suite("Messaging")
    struct Messaging {

        @Test("Client push broadcasts to all subscribers on the topic")
        func pushBroadcastsToAll() async throws {
            let userID = UUID()
            let app1 = try await TestApp(ChatApp.self, assigns: ["userID": userID, "userName": "Alice"])
            let app2 = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Bob"])

            let alice = try await app1.connectSocket("/socket")
            let bob   = try await app2.connectSocket("/socket")

            _ = try await alice.join("room:lobby", payload: [:])
            _ = try await bob.join("room:lobby", payload: [:])

            try await alice.push(event: "new_msg", payload: ["body": "Hello!"])

            let bobReceived = try await bob.receive(event: "new_message")
            #expect(bobReceived["body"] as? String == "Hello!")
            #expect(bobReceived["from"] as? String == "Alice")
        }

        @Test("Server enriches broadcast payload with timestamp")
        func serverEnrichesPayload() async throws {
            let app    = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Alice"])
            let socket = try await app.connectSocket("/socket")
            _ = try await socket.join("room:lobby", payload: [:])

            try await socket.push(event: "new_msg", payload: ["body": "Test"])

            let msg = try await socket.receive(event: "new_message")
            #expect(msg["server_time"] != nil)
        }

        @Test("broadcastFrom does not send to original sender")
        func broadcastFromExcludesSender() async throws {
            let app    = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Alice"])
            let socket = try await app.connectSocket("/socket")
            _ = try await socket.join("room:lobby", payload: [:])

            try await socket.push(event: "typing", payload: [:])

            // Alice should NOT receive her own typing indicator
            let messages = socket.receivedEvents(named: "user_typing")
            #expect(messages.isEmpty)
        }
    }

    // MARK: - Leave

    @Suite("Leave")
    struct Leave {

        @Test("Client can leave a topic gracefully")
        func leaveGracefully() async throws {
            let app    = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Alice"])
            let socket = try await app.connectSocket("/socket")
            _ = try await socket.join("room:lobby", payload: [:])

            let reply = try await socket.leave("room:lobby")
            #expect(reply.status == "ok")
        }

        @Test("Messages are not received after leaving")
        func noMessagesAfterLeave() async throws {
            let app1 = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Alice"])
            let app2 = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Bob"])

            let alice = try await app1.connectSocket("/socket")
            let bob   = try await app2.connectSocket("/socket")

            _ = try await alice.join("room:lobby", payload: [:])
            _ = try await bob.join("room:lobby", payload: [:])
            _ = try await alice.leave("room:lobby")

            // Bob sends a message after Alice left
            try await bob.push(event: "new_msg", payload: ["body": "Still there?"])

            // Alice should receive nothing
            let aliceMessages = alice.receivedEvents(named: "new_message")
            #expect(aliceMessages.isEmpty)
        }
    }

    // MARK: - Server push

    @Suite("Server Push")
    struct ServerPush {

        @Test("Server can push to a topic without a client event")
        func serverPushReachesTopic() async throws {
            let app    = try await TestApp(ChatApp.self, assigns: ["userID": UUID(), "userName": "Alice"])
            let socket = try await app.connectSocket("/socket")
            _ = try await socket.join("system:alerts", payload: [:])

            // Simulate a background job broadcasting an alert
            try await app.channels.broadcast(
                topic: "system:alerts",
                event: "new_alert",
                payload: ["level": "critical", "msg": "DB unreachable"]
            )

            let alert = try await socket.receive(event: "new_alert")
            #expect(alert["level"] as? String == "critical")
        }
    }
}
