# Spec: Metrics and Distributed Tracing

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), Hummingbird metrics/tracing middleware

---

## 1. Goal

Replace the simple `responseTimer()` plug with proper observability.
Hummingbird ships `MetricsMiddleware` and `TracingMiddleware` built on
Apple's `swift-metrics` and `swift-distributed-tracing` packages.

Roost wraps these as plugs and adds a built-in dev dashboard so
developers can see request metrics without setting up Prometheus or
Datadog.

```swift
var plugs: [Plug] {
    [metrics(), requestLogger(), router()]
}
```

In production, wire up a real metrics backend. In development, visit
`/_roost/metrics` for a live view.

---

## 2. Scope

### Part A: Metrics

#### 2.1 Metrics Plug

```swift
public func metrics() -> Plug
```

Records for every request:
- `http_requests_total` — counter by method, path pattern, status.
- `http_request_duration_seconds` — histogram of response times.
- `http_request_size_bytes` — histogram of request body sizes.
- `http_response_size_bytes` — histogram of response body sizes.
- `http_requests_in_flight` — gauge of concurrent requests.

Uses the `swift-metrics` API (`Counter`, `Histogram`, `Gauge`) so any
backend (Prometheus, StatsD, Datadog) works via a metrics factory.

#### 2.2 Built-in Dev Metrics

In dev mode, bootstrap a simple in-memory metrics backend that powers
a `/_roost/metrics` endpoint:

- Request count by route and status code.
- Average and p95 response times.
- Slowest routes.
- Error rate.

JSON response for easy consumption. Only available when
`Roost.env == .dev`.

#### 2.3 Startup Metrics

Log at startup:
- Boot time (from process start to first request accepted).
- Number of registered routes.
- Loaded plugs.

### Part B: Structured Logging

#### 2.4 Request Logger Upgrade

Upgrade the existing `requestLogger()` plug to use `swift-log` with
structured metadata:

```
[2026-03-29 14:22:01] INFO  GET /api/donuts 200 12.3ms
  request_id=abc-123 method=GET path=/api/donuts status=200
  duration_ms=12.3 content_length=1842
```

Include:
- Request ID (from `requestId()` plug if present).
- Method, path, status code.
- Response time in milliseconds.
- Content length.
- Client IP (from `X-Forwarded-For` or socket).

#### 2.5 Log Level by Status

- 2xx → `info`
- 3xx → `info`
- 4xx → `warning`
- 5xx → `error`

### Part C: Distributed Tracing

#### 2.6 Tracing Plug

```swift
public func tracing() -> Plug
```

Wraps Hummingbird's `TracingMiddleware`. Creates a span for each request
with attributes:

- `http.method`
- `http.url`
- `http.status_code`
- `http.route` (pattern, not the actual path)
- `roost.request_id`

Propagates trace context via W3C `traceparent` / `tracestate` headers.

#### 2.7 Database Span Integration

If Spectro supports tracing, create child spans for database queries:

```
[request span] GET /api/donuts
  └── [db span] SELECT * FROM donuts WHERE ...
  └── [db span] SELECT * FROM toppings WHERE donut_id IN ...
```

This is an enhancement — skip if Spectro doesn't expose trace hooks.

---

## 3. Acceptance Criteria

### Metrics

- [ ] `metrics()` plug records request count, duration, size
- [ ] Uses `swift-metrics` API (Counter, Histogram, Gauge)
- [ ] Any `swift-metrics` backend works (Prometheus, StatsD, etc.)
- [ ] Dev mode exposes `/_roost/metrics` JSON endpoint
- [ ] Metrics include method, path pattern, and status code
- [ ] In-flight request gauge tracks concurrent requests

### Logging

- [ ] `requestLogger()` uses `swift-log` with structured metadata
- [ ] Logs include request ID, method, path, status, duration
- [ ] Log level varies by status code (info/warning/error)
- [ ] Client IP extracted from `X-Forwarded-For` or socket

### Tracing

- [ ] `tracing()` plug creates spans per request
- [ ] W3C trace context propagated (`traceparent`, `tracestate`)
- [ ] Span attributes include HTTP method, URL, status, route pattern
- [ ] Works with any `swift-distributed-tracing` backend
- [ ] `swift test` passes

---

## 4. Non-goals

- No built-in Prometheus exporter (use a swift-metrics backend package).
- No health check endpoint (that's application-level, not framework).
- No APM integration (rely on the tracing backend).
- No log file rotation (use the OS or a log backend).
- No dev metrics UI (JSON only — use a tool to visualize).
