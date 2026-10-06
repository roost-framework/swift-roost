import Testing
import RoostTest
@testable import ChatApp

/// Integration specs for Roost.PubSub.
///
/// Uses the in-memory adapter (no external Valkey process required).
/// The in-memory adapter is the default when Roost.env == .test.
@Suite("PubSub Integration Specs")
struct PubSubIntegrationSpecs {

    // MARK: - Subscribe & Receive

    @Suite("Subscribe and Receive")
    struct SubscribeAndReceive {

        @Test("Subscriber receives broadcast on matching topic")
        func receivesMatchingBroadcast() async throws {
            let app = try await TestApp(ChatApp.self)
            var received: [PubSubMessage] = []

            app.pubSub.subscribe("room:lobby") { msg in
                received.append(msg)
            }

            try await app.pubSub.broadcast("room:lobby", event: "new_message", payload: ["body": "Hello"])

            #expect(received.count == 1)
            #expect(received[0].event == "new_message")
            #expect(received[0].payload["body"] as? String == "Hello")
        }

        @Test("Subscriber does not receive broadcast on different topic")
        func ignoresDifferentTopic() async throws {
            let app = try await TestApp(ChatApp.self)
            var received: [PubSubMessage] = []

            app.pubSub.subscribe("room:lobby") { msg in
                received.append(msg)
            }

            try await app.pubSub.broadcast("room:other", event: "new_message", payload: ["body": "Nope"])

            #expect(received.isEmpty)
        }

        @Test("Multiple subscribers all receive the same broadcast")
        func multipleSubscribersReceive() async throws {
            let app = try await TestApp(ChatApp.self)
            var receivedA: [PubSubMessage] = []
            var receivedB: [PubSubMessage] = []

            app.pubSub.subscribe("room:lobby") { receivedA.append($0) }
            app.pubSub.subscribe("room:lobby") { receivedB.append($0) }

            try await app.pubSub.broadcast("room:lobby", event: "ping", payload: [:])

            #expect(receivedA.count == 1)
            #expect(receivedB.count == 1)
        }
    }

    // MARK: - Unsubscribe

    @Suite("Unsubscribe")
    struct Unsubscribe {

        @Test("Unsubscribed handler does not receive further messages")
        func unsubscribeStopsMessages() async throws {
            let app = try await TestApp(ChatApp.self)
            var received: [PubSubMessage] = []

            let token = app.pubSub.subscribe("room:lobby") { received.append($0) }
            try await app.pubSub.broadcast("room:lobby", event: "first", payload: [:])
            #expect(received.count == 1)

            app.pubSub.unsubscribe(token)
            try await app.pubSub.broadcast("room:lobby", event: "second", payload: [:])
            #expect(received.count == 1, "Should not receive after unsubscribe")
        }
    }

    // MARK: - HTTP → PubSub integration

    @Suite("HTTP Broadcast")
    struct HTTPBroadcast {

        @Test("POST /rooms/:id/messages broadcasts to topic")
        func postMessageBroadcasts() async throws {
            let app = try await TestApp(ChatApp.self)
            var received: [PubSubMessage] = []

            app.pubSub.subscribe("room:lobby") { received.append($0) }

            let response = try await app.post(
                "/rooms/lobby/messages",
                json: ["body": "Hello from HTTP"]
            )

            #expect(response.status == .created)
            #expect(received.count == 1)
            #expect(received[0].payload["body"] as? String == "Hello from HTTP")
        }

        @Test("Broadcast payload includes sender metadata")
        func broadcastIncludesMetadata() async throws {
            let app = try await TestApp(ChatApp.self)
            var received: [PubSubMessage] = []

            app.pubSub.subscribe("room:lobby") { received.append($0) }

            _ = try await app.post("/rooms/lobby/messages", json: ["body": "Test"])

            #expect(received.first?.payload["at"] != nil, "Broadcast should include a timestamp")
        }
    }

    // MARK: - Adapter selection

    @Suite("Adapter")
    struct AdapterTests {

        @Test("Test environment uses in-memory adapter by default")
        func usesInMemoryInTests() async throws {
            let app = try await TestApp(ChatApp.self)
            // In-memory adapter is synchronous and doesn't require network
            #expect(app.pubSub is InMemoryPubSub)
        }
    }
}
