// ChannelPatterns.swift
// Design specification for Roost.Channel — inspired by Phoenix.Channel
//
// Channels sit on top of WebSocket + PubSub and implement the Phoenix
// Channel wire protocol so the official phoenix.js client works out of the box.
//
// Wire format: [join_ref, ref, topic, event, payload]
//
// Abstraction layers:
//   ChannelSocket   — one WebSocket connection (one browser tab)
//   ChannelRouter   — maps topic patterns to handler closures
//   ChannelRegistry — actor tracking live sockets per topic (backed by PubSub)

// MARK: - 1. Declare a channel endpoint in your router

struct ChatApp: RoostApp {
    var routes: [Route] {
        // Upgrades GET /socket/websocket to a WebSocket connection
        // All channel topics are multiplexed over this single endpoint.
        channel("/socket")
    }

    // Channel handlers are registered separately from HTTP routes
    var channels: ChannelRouter {
        ChannelRouter {
            // "room:*" matches room:lobby, room:42, room:general, …
            on("room:*", RoomChannel.self)

            // "system:*" for server-side events (e.g. deployments, alerts)
            on("system:*", SystemChannel.self)
        }
    }
}

// MARK: - 2. Define a channel handler

struct RoomChannel: Channel {
    // Called when a client sends the "phx_join" event for this topic
    func join(topic: String, payload: ChannelPayload, socket: ChannelSocket) async throws -> ChannelPayload {
        // Optionally verify the client is allowed to join (e.g. check auth token)
        guard let userID = socket.assigns["userID"] as? UUID else {
            throw ChannelError.unauthorized("Must be authenticated")
        }

        // Track the user's presence on this topic
        try await Presence.track(socket, topic: topic, key: userID.uuidString, meta: [
            "name": socket.assigns["userName"] as? String ?? "Anonymous",
            "online_at": Date().timeIntervalSince1970
        ])

        // Return a reply payload sent back to the joining client
        return ["status": "ok", "room": topic]
    }

    // Called when a client sends a custom event ("new_msg", "typing", etc.)
    func handle(event: String, payload: ChannelPayload, socket: ChannelSocket) async throws {
        switch event {
        case "new_msg":
            let body = payload["body"] as? String ?? ""
            // Broadcast to all subscribers on this topic — including the sender
            try await socket.broadcast(event: "new_message", payload: [
                "body": body,
                "from": socket.assigns["userName"] as? String ?? "Unknown",
                "at":   Date().timeIntervalSince1970
            ])

        case "typing":
            // Broadcast to everyone *except* the sender
            try await socket.broadcastFrom(event: "user_typing", payload: [
                "user": socket.assigns["userName"] as? String ?? "?"
            ])

        default:
            break
        }
    }

    // Called when the client leaves (phx_leave or connection drop)
    func leave(topic: String, payload: ChannelPayload, socket: ChannelSocket) async {
        await Presence.untrack(socket, topic: topic)
    }
}

// MARK: - 3. Channel socket API (available inside handle/join/leave)

// socket.assigns           — typed assigns set during socket authentication
// socket.topic             — the full joined topic string ("room:lobby")
// socket.push(event:payload:)         — send to this client only
// socket.broadcast(event:payload:)    — send to all on this topic
// socket.broadcastFrom(event:payload:) — send to all on this topic except self
// socket.reply(ref:payload:)          — acknowledge a specific client push

// MARK: - 4. Intercepting events server-side (like Phoenix.Channel intercept)

extension RoomChannel {
    // Intercept "new_message" before it fans out so we can log or mutate it
    static var intercepts: [String] { ["new_message"] }

    func intercept(event: String, payload: ChannelPayload, socket: ChannelSocket) async throws -> ChannelPayload {
        // Could persist to DB, filter profanity, add metadata, etc.
        var enriched = payload
        enriched["server_time"] = Date().timeIntervalSince1970
        return enriched  // forward modified payload
        // Or throw ChannelError.halt to drop the message entirely
    }
}

// MARK: - 5. Server-initiated push (outside a request/event handler)

// Inject the ChannelRegistry into a background job to push without a client event:
//
//   struct AlertJob: Job {
//       func execute(parameters: Parameters, context: JobContext) async throws {
//           try await context.channels.broadcast(
//               topic: "system:alerts",
//               event: "new_alert",
//               payload: ["level": "critical", "msg": "DB unreachable"]
//           )
//       }
//   }

// MARK: - 6. Socket authentication (runs once on upgrade, before any join)

// Optionally authenticate the WebSocket handshake using a signed token:
//
//   struct ChatApp: RoostApp {
//       func authenticateSocket(_ conn: Connection) async throws -> SocketAssigns {
//           guard let token = conn.queryParams["token"],
//                 let claims = try? RoostToken.verify(token, secret: secret) else {
//               throw ChannelError.unauthorized("Invalid token")
//           }
//           return ["userID": claims.subject, "userName": claims.name]
//       }
//   }
