import Foundation
import Nexus
import NexusRouter
import Testing

@testable import Roost
@testable import RoostTest

// MARK: - Fixture: Domain types

private struct OrderEvent: Codable, Sendable {
    let orderID: UUID
    let userID:  UUID
    let status:  String
}

// MARK: - Fixture: DashboardApp

private struct DashboardApp: RoostApp {
    // Static so the same broadcaster is shared across all TestApp<DashboardApp> instances.
    static let broadcaster = SSEBroadcaster<OrderEvent>()

    @RouteBuilder var routes: [Route] {
        GET("/live/orders") { conn in
            guard let userID = conn.assigns["currentUser"] as? UUID else {
                return conn.respond(status: .unauthorized)
            }
            let stream = await conn.sseStream(
                from: DashboardApp.broadcaster,
                filter:    { $0.userID == userID },
                eventType: { event in
                    switch event.status {
                    case "confirmed":  return "order_confirmed"
                    case "dispatched": return "order_dispatched"
                    default:           return "order_updated"
                    }
                },
                id: { $0.orderID.uuidString }
            )
            return conn.sse(stream)
        }
    }
}

// MARK: - Tests

@Suite("SSE Integration", .serialized)
struct SSETests {

    // MARK: - Basic streaming

    @Suite("Basic Streaming")
    struct BasicStreaming {

        @Test("SSE endpoint sets correct Content-Type and Cache-Control headers")
        func correctHeaders() async throws {
            let userID = UUID()
            let app    = try await TestApp(DashboardApp.self)
            let head   = try await app.head("/live/orders", assigns: ["currentUser": userID])

            #expect(head.header("Content-Type")?.contains("text/event-stream") == true)
            #expect(head.header("Cache-Control") == "no-cache")
        }

        @Test("Unauthenticated request is rejected with 401")
        func unauthenticatedReturns401() async throws {
            let app      = try await TestApp(DashboardApp.self)
            let response = try await app.get("/live/orders")
            #expect(response.status == .unauthorized)
        }

        @Test("Published events are received by a connected client")
        func receivesPublishedEvents() async throws {
            let userID = UUID()
            let app    = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            let events = try await app.collectSSE("/live/orders", count: 1) {
                await DashboardApp.broadcaster.publish(
                    OrderEvent(orderID: UUID(), userID: userID, status: "confirmed")
                )
            }

            #expect(events.count == 1)
            #expect(events[0].event == "order_confirmed")
        }
    }

    // MARK: - Fan-out

    @Suite("Fan-out")
    struct FanOut {

        @Test("Multiple clients both receive the same published event")
        func multipleClientsReceive() async throws {
            let userID = UUID()
            let app1   = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])
            let app2   = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            // Subscribe both clients (no action yet).
            async let events1 = app1.collectSSE("/live/orders", count: 1) { }
            async let events2 = app2.collectSSE("/live/orders", count: 1) { }

            // Wait for both subscriptions to be registered, then publish.
            await DashboardApp.broadcaster.waitForSubscribers(atLeast: 2)
            await DashboardApp.broadcaster.publish(
                OrderEvent(orderID: UUID(), userID: userID, status: "dispatched")
            )

            let r1 = try await events1
            let r2 = try await events2

            #expect(r1.count == 1)
            #expect(r2.count == 1)
            #expect(r1[0].event == "order_dispatched")
            #expect(r2[0].event == "order_dispatched")
        }

        @Test("Filter: client only receives events matching their userID")
        func filterByUserID() async throws {
            let aliceID     = UUID()
            let bobID       = UUID()
            let aliceOrderID = UUID()
            let app          = try await TestApp(DashboardApp.self, assigns: ["currentUser": aliceID])

            let events = try await app.collectSSE("/live/orders", count: 1, timeout: .seconds(2)) {
                // Bob's event — Alice should NOT receive it
                await DashboardApp.broadcaster.publish(
                    OrderEvent(orderID: UUID(), userID: bobID, status: "confirmed")
                )
                // Alice's event — she SHOULD receive it
                await DashboardApp.broadcaster.publish(
                    OrderEvent(orderID: aliceOrderID, userID: aliceID, status: "confirmed")
                )
            }

            #expect(events.count == 1)
            let decoded = try events[0].decodeData(OrderEvent.self)
            #expect(decoded.userID == aliceID)
        }
    }

    // MARK: - Event Format

    @Suite("Event Format")
    struct EventFormat {

        @Test("event: field maps correctly to status")
        func eventFieldMatchesStatus() async throws {
            let userID = UUID()
            let app    = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            let events = try await app.collectSSE("/live/orders", count: 3) {
                for status in ["confirmed", "dispatched", "delivered"] {
                    await DashboardApp.broadcaster.publish(
                        OrderEvent(orderID: UUID(), userID: userID, status: status)
                    )
                }
            }

            #expect(events[0].event == "order_confirmed")
            #expect(events[1].event == "order_dispatched")
            #expect(events[2].event == "order_updated")  // "delivered" → fallback
        }

        @Test("id: field contains the orderID")
        func eventIncludesID() async throws {
            let userID  = UUID()
            let orderID = UUID()
            let app     = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            let events = try await app.collectSSE("/live/orders", count: 1) {
                await DashboardApp.broadcaster.publish(
                    OrderEvent(orderID: orderID, userID: userID, status: "confirmed")
                )
            }

            #expect(events[0].id == orderID.uuidString)
        }

        @Test("data: field is JSON-encoded")
        func eventDataIsJSON() async throws {
            let userID  = UUID()
            let orderID = UUID()
            let app     = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            let events = try await app.collectSSE("/live/orders", count: 1) {
                await DashboardApp.broadcaster.publish(
                    OrderEvent(orderID: orderID, userID: userID, status: "confirmed")
                )
            }

            let decoded = try events[0].decodeData(OrderEvent.self)
            #expect(decoded.orderID == orderID)
            #expect(decoded.status == "confirmed")
        }
    }
}
