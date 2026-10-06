import Foundation
import Metrics
import Nexus

// MARK: - DevMetricsStore

/// In-memory metrics store for the dev endpoint. Thread-safe via a private lock.
public final class DevMetricsStore: @unchecked Sendable {
    public struct RouteStats: Sendable, Codable {
        public let path: String
        public let avgMs: Double
    }

    public struct Snapshot: Sendable, Codable {
        public let totalRequests: Int
        public let avgDurationMs: Double
        public let p95DurationMs: Double
        public let errorRate: Double
        public let requestsByStatus: [String: Int]
        public let slowestRoutes: [RouteStats]

        enum CodingKeys: String, CodingKey {
            case totalRequests = "total_requests"
            case avgDurationMs = "avg_duration_ms"
            case p95DurationMs = "p95_duration_ms"
            case errorRate = "error_rate"
            case requestsByStatus = "requests_by_status"
            case slowestRoutes = "slowest_routes"
        }
    }

    private let lock = NSLock()
    private var _requestCount: Int = 0
    private var _errorCount: Int = 0
    private var _durations: [Double] = []
    private var _statusCounts: [Int: Int] = [:]
    private var _routeDurations: [String: [Double]] = [:]

    public init() {}

    public func record(method: String, path: String, status: Int, durationMs: Double) {
        lock.lock()
        defer { lock.unlock() }
        _requestCount += 1
        _durations.append(durationMs)
        _statusCounts[status, default: 0] += 1
        _routeDurations[path, default: []].append(durationMs)
        if status >= 400 {
            _errorCount += 1
        }
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }

        let total = _requestCount
        let avgMs = _durations.isEmpty ? 0 : _durations.reduce(0, +) / Double(_durations.count)
        let sorted = _durations.sorted()
        let p95Index = min(Int(Double(sorted.count) * 0.95), max(sorted.count - 1, 0))
        let p95 = sorted.isEmpty ? 0 : sorted[p95Index]
        let errorRate = total == 0 ? 0 : Double(_errorCount) / Double(total)

        let slowest = _routeDurations
            .map { path, durs in
                RouteStats(path: path, avgMs: durs.reduce(0, +) / Double(durs.count))
            }
            .sorted { $0.avgMs > $1.avgMs }
            .prefix(5)

        return Snapshot(
            totalRequests: total,
            avgDurationMs: round(avgMs * 10) / 10,
            p95DurationMs: round(p95 * 10) / 10,
            errorRate: round(errorRate * 10_000) / 10_000,
            requestsByStatus: Dictionary(
                uniqueKeysWithValues: _statusCounts.map { (String($0.key), $0.value) }),
            slowestRoutes: Array(slowest)
        )
    }

    public func snapshotJSON() -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let data = try! encoder.encode(snapshot())
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Shared store

private let sharedDevStore = DevMetricsStore()

/// Returns the shared DevMetricsStore so users can read snapshots programmatically.
public func sharedMetricsStore() -> DevMetricsStore {
    sharedDevStore
}

// MARK: - Metrics Plug

/// A Nexus plug that records HTTP metrics using swift-metrics.
///
/// Tracks:
/// - `http_requests_total` counter (dimensions: method, status)
/// - `http_request_duration_seconds` histogram
/// - `http_requests_in_flight` gauge
///
/// Also records to the in-memory DevMetricsStore for the dev endpoint.
///
/// ```swift
/// var plugs: [Plug] {
///     [metrics(), requestLogger()]
/// }
/// ```
public func metrics() -> Plug {
    let counter = Counter(
        label: "http_requests_total",
        dimensions: []
    )
    let histogram = Recorder(
        label: "http_request_duration_seconds",
        dimensions: [],
        aggregate: true
    )
    let inFlightGauge = Meter(label: "http_requests_in_flight", dimensions: [])

    return { conn in
        inFlightGauge.increment()
        let start = ContinuousClock.now

        return conn.registerBeforeSend { c in
            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            let ms = seconds * 1000

            let method = String(describing: c.request.method)
            let status = c.response.status.code

            counter.increment()
            histogram.record(seconds)
            inFlightGauge.decrement()

            // Record for dev endpoint
            let path = c.request.path ?? ""
            sharedDevStore.record(
                method: method,
                path: path,
                status: status,
                durationMs: ms
            )

            return c
        }
    }
}

// MARK: - Dev Metrics Endpoint

/// A plug that serves metrics as JSON at `/_roost/metrics`.
///
/// Only meaningful in development mode. Opt-in.
///
/// ```swift
/// var plugs: [Plug] {
///     [metrics(), devMetricsEndpoint(), requestLogger()]
/// }
/// ```
public func devMetricsEndpoint() -> Plug {
    { conn in
        guard conn.request.path == "/_roost/metrics" else {
            return conn
        }

        var result = conn
        result.isHalted = true
        result.response.status = .ok
        result.response.headerFields[.contentType] = "application/json"
        result.responseBody = .string(sharedDevStore.snapshotJSON())
        return result
    }
}
