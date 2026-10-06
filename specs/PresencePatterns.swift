// PresencePatterns.swift
// Design specification for Roost.Presence — inspired by Phoenix.Presence
//
// Presence tracks which users are currently connected to a Channel topic,
// broadcasts join/leave diffs to all subscribers, and provides a consistent
// view of the online list even across multiple nodes.
//
// Implementation layers:
//   Phase 1 (in-memory):  Actor-based dictionary per topic. Single node.
//   Phase 2 (distributed): Valkey HSET with TTL heartbeat + PubSub diffs.

// MARK: - 1. Track a socket on join

struct RoomChannel: Channel {
    func join(topic: String, payload: ChannelPayload, socket: ChannelSocket) async throws -> ChannelPayload {
        let userID   = socket.assigns["userID"] as! UUID
        let userName = socket.assigns["userName"] as? String ?? "Anonymous"

        // Register this socket in the presence system for the topic.
        // Automatically broadcasts a "presence_diff" join event to all other subscribers.
        try await Presence.track(socket, topic: topic, key: userID.uuidString, meta: [
            "name":      userName,
            "online_at": Date().timeIntervalSince1970,
        ])

        // Include the current presence list in the join reply so the client
        // can render the user list without a separate round-trip.
        let currentPresence = try await Presence.list(topic)
        return ["status": "ok", "presence": currentPresence]
    }

    func leave(topic: String, payload: ChannelPayload, socket: ChannelSocket) async {
        let userID = socket.assigns["userID"] as! UUID
        // Untrack: automatically broadcasts a "presence_diff" leave event.
        await Presence.untrack(socket, topic: topic, key: userID.uuidString)
    }
}

// MARK: - 2. List current presence on a topic

// Server-side query (e.g. from an HTTP endpoint):
//
//   func onlineUsers(_ conn: Connection) async throws -> Connection {
//       let users = try await conn.presence.list("room:lobby")
//       // users: [PresenceEntry(key: "uuid-string", metas: [[String: Any]])]
//       let names = users.map { $0.metas.first?["name"] as? String ?? "?" }
//       return conn.json(status: .ok, value: ["users": names])
//   }

// MARK: - 3. Presence diff events received by clients

// When any socket joins or leaves, all remaining subscribers on the topic
// receive a "presence_diff" push with two keys:
//
//   {
//     "joins":  { "<key>": { "metas": [{ "name": "Alice", "online_at": 1234567890.0 }] } },
//     "leaves": { "<key>": { "metas": [{ "name": "Bob",   "online_at": 1234560000.0 }] } }
//   }
//
// This matches the Phoenix Presence diff format, so the phoenix.js Presence
// helper (Presence.syncDiff, Presence.syncState) works without modification.

// MARK: - 4. Multiple metas per key (same user, multiple tabs)

// If the same key (userID) joins from two browser tabs, both metas are stored:
//
//   Presence.list("room:lobby")
//   // [PresenceEntry(key: "user-abc", metas: [
//   //     ["name": "Alice", "phx_ref": "ref1", "online_at": ...],
//   //     ["name": "Alice", "phx_ref": "ref2", "online_at": ...]
//   // ])]
//
// When both tabs are closed the "leaves" diff fires once both metas are gone.

// MARK: - 5. PresenceEntry value type

// struct PresenceEntry {
//     let key:   String               // typically userID.uuidString
//     let metas: [[String: any Sendable]]   // one entry per joined socket for this key
// }

// MARK: - 6. Presence.list returns a stable, sorted view

// try await Presence.list("room:lobby")
// Returns entries sorted by the earliest online_at across all metas.
// Guarantees the same order for every subscriber on every node.

// MARK: - 7. Distributed heartbeat (Phase 2, Valkey-backed)

// In distributed mode each node periodically runs:
//   try await Presence.heartbeat()   // called automatically every 15s
// This refreshes the TTL on all metas tracked by this node.
// Stale entries (node crashed without clean leave) expire automatically
// and trigger "presence_diff" leaves via Valkey keyspace notifications.
