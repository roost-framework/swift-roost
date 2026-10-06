// SSEPatterns.swift
// Design specification for Roost SSE (Server-Sent Events)
//
// Backed by sse-kit (hummingbird-project).
// Converts any AsyncSequence<ServerSentEvent> into a streaming HTTP response
// with Content-Type: text/event-stream.
//
// Great for: live dashboards, order status updates, log tailing, notifications.
// Not a replacement for Channels — SSE is unidirectional (server → client only).

// MARK: - 1. Simple SSE endpoint — counter that increments every second

import Foundation

func counterSSE(_ conn: Connection) async throws -> Connection {
    // SSEBroadcaster is a Roost actor that fans out to all connected listeners
    let stream = conn.sseStream(from: conn.app.counterBroadcaster)
    return conn.sse(stream)  // sets Content-Type: text/event-stream, Cache-Control: no-cache
}

// MARK: - 2. SSEBroadcaster — a reusable fan-out actor (provided by Roost)

// actor SSEBroadcaster<T: Sendable>: Service {
//     // Publish a value; all current subscribers receive it
//     func publish(_ value: T) async
//
//     // Returns an AsyncStream<T> for one subscriber; auto-removes on cancellation
//     func makeStream() -> AsyncStream<T>
//
//     // run() is called by ServiceGroup; keeps the actor alive
//     func run() async throws
// }

// MARK: - 3. App-level broadcaster registration

struct DashboardApp: RoostApp {
    // Broadcaster is a Service; Roost registers it in the ServiceGroup
    var orderBroadcaster: SSEBroadcaster<OrderEvent>   = SSEBroadcaster()
    var metricsBroadcaster: SSEBroadcaster<MetricSnap> = SSEBroadcaster()

    var routes: [Route] {
        [
            get("/live/orders",  orderStatusSSE),
            get("/live/metrics", metricsSSE),
        ]
    }
}

// MARK: - 4. Order status stream — typed events

func orderStatusSSE(_ conn: Connection) async throws -> Connection {
    guard let userID = conn.assigns["currentUser"] as? UUID else {
        return conn.halt(status: .unauthorized)
    }

    // Filter the broadcaster to only events relevant to this user
    let stream = conn.sseStream(from: conn.app.orderBroadcaster) { event in
        event.userID == userID
    }

    return conn.sse(stream, eventType: { event in
        // The event name sent in the SSE `event:` field
        switch event.status {
        case "confirmed":  return "order_confirmed"
        case "dispatched": return "order_dispatched"
        default:           return "order_updated"
        }
    }, id: { event in
        event.orderID.uuidString   // SSE `id:` field for reconnection
    })
}

// MARK: - 5. Pushing to the broadcaster from a background job

struct OrderShippedJob: RoostJob {
    struct Parameters: Codable { let orderID: UUID; let userID: UUID }

    func execute(parameters: Parameters, context: JobContext) async throws {
        try await context.spectro.update(Order.self, id: parameters.orderID, set: \.status, to: "dispatched")

        // Push to any currently connected SSE subscribers
        await context.app.orderBroadcaster.publish(OrderEvent(
            orderID: parameters.orderID,
            userID:  parameters.userID,
            status:  "dispatched"
        ))
    }
}

// MARK: - 6. Client-side JavaScript (no library needed)

// const source = new EventSource("/live/orders");
//
// source.addEventListener("order_confirmed", (e) => {
//     const data = JSON.parse(e.data);
//     showToast(`Order ${data.orderId} confirmed!`);
// });
//
// source.addEventListener("order_dispatched", (e) => {
//     updateOrderStatus(JSON.parse(e.data));
// });
//
// source.onerror = () => { /* browser auto-reconnects after 3s */ };

// MARK: - 7. conn.sse API

// conn.sse(_ stream: AsyncStream<ServerSentEvent>) -> Connection
//   Sets headers: Content-Type: text/event-stream, Cache-Control: no-cache, X-Accel-Buffering: no
//   Returns a streaming response body; Hummingbird flushes each event as it arrives.

// conn.sseStream(from broadcaster: SSEBroadcaster<T>, filter: ...) -> AsyncStream<ServerSentEvent>
//   Subscribes to the broadcaster, maps T → ServerSentEvent (JSON-encodes the value as `data:`).

// MARK: - 8. Typed event value types

// struct OrderEvent: Codable, Sendable {
//     let orderID: UUID
//     let userID:  UUID
//     let status:  String
// }
//
// struct MetricSnap: Codable, Sendable {
//     let timestamp: Date
//     let cpuPct:    Double
//     let memMB:     Int
// }
