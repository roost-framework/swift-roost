// PubSubPatterns.swift
// Design specification for Roost.PubSub — inspired by Phoenix.PubSub
//
// Two adapters, one interface:
//   .inMemory()  — actor-based, no external deps (dev, test)
//   .valkey(...)  — distributed, backed by valkey-swift PUBLISH/SUBSCRIBE (production)
//
// The adapter is configured once at app startup and injected into the
// Connection via an assign key, just like `conn.spectro`.

// MARK: - 1. App-level configuration

struct ChatApp: RoostApp {
    var pubSub: some RoostPubSub {
        // In dev/test: in-memory actor (no external process needed)
        if Roost.env == .test || Roost.env == .dev {
            return PubSub.inMemory()
        }
        // In production: Valkey-backed, distributed across all nodes
        return PubSub.valkey(url: ProcessInfo.processInfo.environment["VALKEY_URL"] ?? "valkey://localhost:6379")
    }

    var routes: [Route] {
        // ...
        []
    }
}

// MARK: - 2. Subscribe from within a request handler or plug

func roomPlug(_ conn: Connection) -> Connection {
    let topic = "room:\(conn.params["id"] ?? "lobby")"

    // Subscribe this process to a topic; messages arrive via AsyncSequence
    conn.pubSub.subscribe(topic) { message in
        // message: PubSubMessage(topic:, event:, payload:)
        print("Received \(message.event) on \(message.topic): \(message.payload)")
    }

    return conn
}

// MARK: - 3. Broadcast from anywhere

func postMessage(_ conn: Connection) async throws -> Connection {
    let topic = "room:lobby"
    let body   = conn.bodyParams["body"] ?? ""

    // Fans out to every subscriber on this topic — local or remote
    try await conn.pubSub.broadcast(topic, event: "new_message", payload: ["body": body])

    return conn.json(status: .created, value: ["ok": true])
}

// MARK: - 4. Unsubscribe

func leaveRoom(_ conn: Connection) -> Connection {
    conn.pubSub.unsubscribe("room:lobby")
    return conn.json(status: .ok, value: ["ok": true])
}

// MARK: - 5. PubSub protocol — the interface both adapters implement

// protocol RoostPubSub: Sendable {
//     func subscribe(_ topic: String, handler: @escaping @Sendable (PubSubMessage) async -> Void)
//     func broadcast(_ topic: String, event: String, payload: [String: Any]) async throws
//     func unsubscribe(_ topic: String)
// }

// MARK: - 6. PubSubMessage value type

// struct PubSubMessage: Sendable {
//     let topic:   String
//     let event:   String
//     let payload: [String: any Sendable]
// }

// MARK: - 7. Testing with in-memory adapter (no Valkey required)

// In tests, use the default .inMemory() adapter:
//
//   let app = try await TestApp(ChatApp.self)
//   var received: [PubSubMessage] = []
//
//   app.pubSub.subscribe("room:lobby") { msg in
//       received.append(msg)
//   }
//
//   let _ = try await app.post("/rooms/lobby/messages", json: ["body": "Hello"])
//   #expect(received.count == 1)
//   #expect(received[0].event == "new_message")
