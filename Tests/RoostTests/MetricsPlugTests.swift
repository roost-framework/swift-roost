import Foundation
import HTTPTypes
import Metrics
import Nexus
import NexusTest
import Testing

@testable import Roost

// MARK: - Helpers

private func buildConn(
    method: HTTPRequest.Method = .get,
    path: String = "/"
) -> Connection {
    var conn = TestConnection.build()
    conn.request.method = method
    conn.request.url = URL(string: "http://localhost\(path)")
    return conn
}

private func runPlug(_ conn: Connection, plug: Plug) async throws -> Connection {
    try await plug(conn)
}

// MARK: - Metrics Plug (smoke tests)

@Suite("Metrics Plug")
struct MetricsPlugTests {

    @Test("metrics plug runs without error")
    func metricsPlugRuns() async throws {
        let plug = metrics()
        let conn = buildConn(method: .get, path: "/api/users")

        // Applying the plug should not throw
        let result = try await runPlug(conn, plug: plug)
        #expect(!result.isHalted)
    }

    @Test("metrics plug registers beforeSend handler")
    func metricsPlugRegistersBeforeSend() async throws {
        let plug = metrics()
        let conn = buildConn(method: .post, path: "/api/data")

        let result = try await runPlug(conn, plug: plug)
        // Running beforeSend should not throw
        let final = result.runBeforeSend()
        #expect(!final.isHalted)
    }
}

// MARK: - DevMetricsStore Tests

@Suite("DevMetricsStore")
struct DevMetricsStoreTests {

    @Test("snapshot produces valid structure")
    func snapshotProducesValidStructure() {
        let store = DevMetricsStore()
        store.record(method: "GET", path: "/api", status: 200, durationMs: 45.2)
        store.record(method: "POST", path: "/api", status: 201, durationMs: 120.5)
        store.record(method: "GET", path: "/api", status: 500, durationMs: 5.0)

        let snapshot = store.snapshot()

        #expect(snapshot.totalRequests == 3)
        #expect(snapshot.requestsByStatus["200"] == 1)
        #expect(snapshot.requestsByStatus["201"] == 1)
        #expect(snapshot.requestsByStatus["500"] == 1)
    }

    @Test("snapshot JSON round-trips correctly")
    func snapshotJSONRoundTrip() {
        let store = DevMetricsStore()
        store.record(method: "GET", path: "/api", status: 200, durationMs: 42.0)

        let json = store.snapshotJSON()
        let data = json.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(DevMetricsStore.Snapshot.self, from: data)

        #expect(decoded.totalRequests == 1)
    }

    @Test("snapshot with no records returns zeros")
    func emptySnapshotReturnsZeros() {
        let store = DevMetricsStore()
        let snapshot = store.snapshot()

        #expect(snapshot.totalRequests == 0)
        #expect(snapshot.avgDurationMs == 0)
        #expect(snapshot.p95DurationMs == 0)
        #expect(snapshot.errorRate == 0)
        #expect(snapshot.slowestRoutes.isEmpty)
    }

    @Test("snapshot correctly computes error rate")
    func snapshotComputesErrorRate() {
        let store = DevMetricsStore()
        store.record(method: "GET", path: "/ok", status: 200, durationMs: 10)
        store.record(method: "GET", path: "/fail", status: 500, durationMs: 10)
        store.record(method: "GET", path: "/notfound", status: 404, durationMs: 10)

        let snapshot = store.snapshot()
        // 404 and 500 are >= 400, so 2 errors out of 3
        #expect(abs(snapshot.errorRate - 2.0 / 3.0) < 0.0001)
    }

    @Test("snapshot groups by route path")
    func snapshotGroupsByPath() {
        let store = DevMetricsStore()
        store.record(method: "GET", path: "/users", status: 200, durationMs: 10)
        store.record(method: "GET", path: "/users", status: 200, durationMs: 20)
        store.record(method: "GET", path: "/posts", status: 200, durationMs: 50)

        let snapshot = store.snapshot()
        let routeAverages = Dictionary(
            uniqueKeysWithValues: snapshot.slowestRoutes.map { ($0.path, $0.avgMs) }
        )
        #expect(routeAverages["/users"] == 15.0)
        #expect(routeAverages["/posts"] == 50.0)
    }

    @Test("sharedMetricsStore returns the same instance")
    func sharedStoreIsSingleton() {
        let store1 = sharedMetricsStore()
        let store2 = sharedMetricsStore()
        #expect(store1 === store2)
    }

    @Test("devMetricsEndpoint responds to correct path")
    func devMetricsEndpointRespondsToCorrectPath() async throws {
        let conn = buildConn(method: .get, path: "/_roost/metrics")
        // Run metrics plug first to populate the store
        let plug = metrics()
        _ = try await plug(conn)

        let endpointPlug = devMetricsEndpoint()
        let result = try await endpointPlug(conn)

        #expect(result.isHalted)
        #expect(result.response.status == .ok)
        #expect(result.response.headerFields[.contentType] == "application/json")
    }

    @Test("devMetricsEndpoint passes through for other paths")
    func devMetricsEndpointPassesThrough() async throws {
        let conn = buildConn(method: .get, path: "/other")
        let endpointPlug = devMetricsEndpoint()
        let result = try await endpointPlug(conn)

        #expect(!result.isHalted)
    }
}
