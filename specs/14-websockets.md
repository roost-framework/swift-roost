# Spec: WebSocket Channels

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), Hummingbird WebSocket package

---

## 1. Goal

Real-time communication without LiveView. Phoenix has Channels, Rails has
ActionCable — Roost needs a way to push updates to connected clients.

`hummingbird-websocket` already provides the low-level WebSocket upgrade,
framing, and compression. Roost wraps it into a channel abstraction
that feels native to the framework's plug-based architecture.

```swift
// In routes:
ws("/chat/:room", to: ChatChannel.self)

// Channel definition:
struct ChatChannel: RoostChannel {
    func onJoin(socket: WebSocket, params: ChannelParams) async {
        socket.send("Welcome to \(params["room"]!)")
    }

    func onMessage(socket: WebSocket, message: String) async {
        broadcast(to: params["room"]!, message: message)
    }

    func onLeave(socket: WebSocket) async { }
}
```

One route declaration. Structured handlers. Broadcasting built in.

---

## 2. Scope

### 2.1 Dependencies

Add `hummingbird-websocket` to Package.swift:

```swift
.package(
    url: "https://github.com/hummingbird-project/hummingbird-websocket.git",
    from: "2.0.0"
)
```

Products needed: `HummingbirdWebSocket` (server-side upgrade).

### 2.2 RoostChannel Protocol

```swift
public protocol RoostChannel: Sendable {
    /// Called when a client connects and the WebSocket upgrade succeeds.
    func onJoin(socket: WebSocket, params: ChannelParams) async throws

    /// Called for each text message received from the client.
    func onMessage(socket: WebSocket, message: String) async throws

    /// Called for each binary message received from the client.
    func onData(socket: WebSocket, data: Data) async throws

    /// Called when the client disconnects or the connection drops.
    func onLeave(socket: WebSocket) async
}
```

Default implementations:
- `onData` — default no-op (most channels are text-based).
- `onLeave` — default no-op.

### 2.3 ChannelParams

A dictionary of route parameters and query parameters available in
channel handlers:

```swift
public struct ChannelParams: Sendable {
    public let pathParams: [String: String]   // from route pattern
    public let queryParams: [String: String]  // from URL query string
    public subscript(_ key: String) -> String? { ... }
}
```

### 2.4 WebSocket Type

A wrapper around Hummingbird's WebSocket that provides a clean send API:

```swift
public struct WebSocket: Sendable {
    /// Send a text message to this client.
    public func send(_ text: String) async throws

    /// Send binary data to this client.
    public func send(_ data: Data) async throws

    /// Close the connection with an optional reason.
    public func close(code: WebSocketCloseCode = .normalClosure) async throws
}
```

### 2.5 Broadcasting

A `ChannelRegistry` that tracks connected sockets by topic (room/channel
name). Channels can broadcast to all sockets on a topic:

```swift
public enum Broadcast {
    /// Send to all connected sockets on a topic.
    static func send(to topic: String, message: String) async

    /// Send to all connected sockets on a topic except the sender.
    static func sendOthers(
        to topic: String,
        except: WebSocket,
        message: String
    ) async
}
```

The registry is an actor to ensure thread safety:

```swift
actor ChannelRegistry {
    private var channels: [String: [WebSocketID: WebSocket]] = [:]

    func join(topic: String, socket: WebSocket) -> WebSocketID { ... }
    func leave(topic: String, id: WebSocketID) { ... }
    func broadcast(topic: String, message: String) async { ... }
    func broadcastExcept(
        topic: String,
        except: WebSocketID,
        message: String
    ) async { ... }
}
```

### 2.6 Route Integration

WebSocket routes are declared alongside HTTP routes using a `ws` helper:

```swift
var routes: some RouteComponent {
    GET("/") { conn in
        conn |> render("index")
    }
    ws("/chat/:room", to: ChatChannel.self)
    ws("/notifications", to: NotificationChannel.self)
}
```

The `ws` function:
1. Registers an HTTP GET route that handles the WebSocket upgrade.
2. On upgrade, creates a `ChannelParams` from the route/query params.
3. Instantiates the channel, calls `onJoin`.
4. Enters a read loop calling `onMessage`/`onData` for each frame.
5. On disconnect, calls `onLeave` and removes from the registry.

### 2.7 Heartbeat / Ping-Pong

Hummingbird handles WebSocket ping/pong at the protocol level. Roost
adds an application-level heartbeat:

- Server sends a ping every 30 seconds (configurable).
- If no pong received within 10 seconds, connection is closed.
- This detects dead connections that the TCP stack might not catch.

### 2.8 Authentication in Channels

Channels can access the connection's assigns (session, current user) if
the WebSocket upgrade request passed through the plug pipeline:

```swift
func onJoin(socket: WebSocket, params: ChannelParams) async throws {
    guard let userId = params.assigns["current_user_id"] else {
        try await socket.close(code: .policyViolation)
        return
    }
    // Authenticated — proceed
}
```

This requires the plug pipeline to run before the WebSocket upgrade,
which is the default behavior.

---

## 3. Acceptance Criteria

- [ ] `hummingbird-websocket` added as a dependency
- [ ] `RoostChannel` protocol with `onJoin`, `onMessage`, `onData`, `onLeave`
- [ ] `WebSocket` wrapper with `send(text)`, `send(data)`, `close`
- [ ] `ChannelParams` with path and query params
- [ ] `Broadcast.send(to:message:)` sends to all clients on a topic
- [ ] `Broadcast.sendOthers(to:except:message:)` excludes the sender
- [ ] `ChannelRegistry` actor manages connected sockets per topic
- [ ] `ws()` route helper integrates with existing route declarations
- [ ] Plug pipeline runs before WebSocket upgrade (auth works)
- [ ] Heartbeat ping every 30 seconds with 10-second timeout
- [ ] Clean disconnect handling (onLeave called, socket removed from registry)
- [ ] Multiple channels on different routes work simultaneously
- [ ] `swift test` passes (use HummingbirdWSTesting for channel tests)

---

## 4. Non-goals

- No client-side JavaScript library (use the browser's native WebSocket API).
- No channel multiplexing over a single connection (one connection = one channel).
- No presence tracking (who's online) — can be built on top of the registry.
- No PubSub across server instances (single-node only; Redis PubSub later).
- No automatic reconnection logic (that's a client concern).
- No LiveView / server-rendered DOM diffing.
