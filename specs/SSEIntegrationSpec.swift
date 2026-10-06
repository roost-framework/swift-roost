import Testing
import RoostTest
@testable import DashboardApp

/// Integration specs for Roost Server-Sent Events.
///
/// RoostTest provides `collectSSE(path:count:timeout:)` which connects
/// to an SSE endpoint, collects N events, then disconnects — all in-process.
@Suite("SSE Integration Specs")
struct SSEIntegrationSpecs {

    // MARK: - Basic streaming

    @Suite("Basic Streaming")
    struct BasicStreaming {

        @Test("SSE endpoint responds with correct content-type")
        func correctContentType() async throws {
            let app  = try await TestApp(DashboardApp.self)
            let head = try await app.head("/live/orders", assigns: ["currentUser": UUID()])

            #expect(head.header("Content-Type")?.contains("text/event-stream") == true)
            #expect(head.header("Cache-Control") == "no-cache")
        }

        @Test("Unauthenticated request is rejected")
        func unauthenticatedReturns401() async throws {
            let app      = try await TestApp(DashboardApp.self)
            // No currentUser assign → should halt with 401
            let response = try await app.get("/live/orders")
            #expect(response.status == .unauthorized)
        }

        @Test("Published events are received by a connected client")
        func receivesPublishedEvents() async throws {
            let userID = UUID()
            let app    = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            // Start collecting 1 event from the SSE stream (async, in background)
            async let events = app.collectSSE("/live/orders", count: 1)

            // Publish an event to the broadcaster
            await app.orderBroadcaster.publish(OrderEvent(
                orderID: UUID(),
                userID:  userID,
                status:  "confirmed"
            ))

            let received = try await events
            #expect(received.count == 1)
            #expect(received[0].event == "order_confirmed")
        }
    }

    // MARK: - Fan-out

    @Suite("Fan-out")
    struct FanOut {

        @Test("Multiple clients all receive the same published event")
        func multipleClientsReceive() async throws {
            let userID = UUID()
            let app1   = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])
            let app2   = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            async let events1 = app1.collectSSE("/live/orders", count: 1)
            async let events2 = app2.collectSSE("/live/orders", count: 1)

            let event = OrderEvent(orderID: UUID(), userID: userID, status: "dispatched")
            await app1.orderBroadcaster.publish(event)

            let received1 = try await events1
            let received2 = try await events2

            #expect(received1.count == 1)
            #expect(received2.count == 1)
            #expect(received1[0].event == "order_dispatched")
        }

        @Test("Filter: client only receives events matching their userID")
        func filterByUserID() async throws {
            let aliceID = UUID()
            let bobID   = UUID()
            let app     = try await TestApp(DashboardApp.self, assigns: ["currentUser": aliceID])

            async let events = app.collectSSE("/live/orders", count: 1, timeout: .milliseconds(500))

            // Publish an event for Bob — Alice should NOT receive it
            await app.orderBroadcaster.publish(OrderEvent(
                orderID: UUID(), userID: bobID, status: "confirmed"
            ))

            // Publish an event for Alice — she SHOULD receive it
            let aliceEvent = OrderEvent(orderID: UUID(), userID: aliceID, status: "confirmed")
            await app.orderBroadcaster.publish(aliceEvent)

            let received = try await events
            #expect(received.count == 1)
            let data = try received[0].decodeData(OrderEvent.self)
            #expect(data.userID == aliceID)
        }
    }

    // MARK: - SSE event format

    @Suite("Event Format")
    struct EventFormat {

        @Test("Event includes correct `event:` field based on status")
        func eventFieldMatchesStatus() async throws {
            let userID = UUID()
            let app    = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            async let events = app.collectSSE("/live/orders", count: 3)

            for status in ["confirmed", "dispatched", "delivered"] {
                await app.orderBroadcaster.publish(OrderEvent(
                    orderID: UUID(), userID: userID, status: status
                ))
            }

            let received = try await events
            #expect(received[0].event == "order_confirmed")
            #expect(received[1].event == "order_dispatched")
            #expect(received[2].event == "order_updated")   // "delivered" → fallback
        }

        @Test("Event includes `id:` field for reconnection")
        func eventIncludesID() async throws {
            let userID  = UUID()
            let orderID = UUID()
            let app     = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            async let events = app.collectSSE("/live/orders", count: 1)
            await app.orderBroadcaster.publish(OrderEvent(orderID: orderID, userID: userID, status: "confirmed"))

            let received = try await events
            #expect(received[0].id == orderID.uuidString)
        }

        @Test("Event data is JSON-encoded")
        func eventDataIsJSON() async throws {
            let userID  = UUID()
            let orderID = UUID()
            let app     = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            async let events = app.collectSSE("/live/orders", count: 1)
            await app.orderBroadcaster.publish(OrderEvent(orderID: orderID, userID: userID, status: "confirmed"))

            let received = try await events
            let decoded  = try received[0].decodeData(OrderEvent.self)
            #expect(decoded.orderID == orderID)
            #expect(decoded.status == "confirmed")
        }
    }

    // MARK: - Job → SSE integration

    @Suite("Job to SSE")
    struct JobToSSE {

        @Test("OrderShippedJob publishes to SSE broadcaster")
        func jobPublishesToSSE() async throws {
            let userID  = UUID()
            let orderID = UUID()
            let app     = try await TestApp(DashboardApp.self, assigns: ["currentUser": userID])

            let order = Order(id: orderID, userID: userID, userEmail: "test@example.com", status: "pending")
            try await app.spectro.insert(order)

            async let events = app.collectSSE("/live/orders", count: 1)

            try await app.jobs.push(OrderShippedJob.self, parameters: .init(
                orderID: orderID,
                userID:  userID
            ))

            let received = try await events
            #expect(received.count == 1)
            #expect(received[0].event == "order_dispatched")
        }
    }
}
