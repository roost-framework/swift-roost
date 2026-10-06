import Foundation
import HTTPTypes
import Nexus
import Tracing

// MARK: - Tracing Plug

/// A Nexus plug that creates a distributed tracing span for each request.
///
/// Features:
/// - Creates a span per request using swift-distributed-tracing
/// - Propagates W3C trace context via traceparent/tracestate headers
/// - Records attributes: http.method, http.url, http.status_code, roost.request_id
///
/// ```swift
/// var plugs: [Plug] {
///     [tracing(), requestLogger()]
/// }
/// ```
public func tracing() -> Plug {
    { conn in
        let requestId = UUID().uuidString
        var initial = conn
        initial.assigns["request_id"] = requestId

        let spanName = conn.request.method.rawValue + " "
            + (conn.request.path ?? "/")

        let span = InstrumentationSystem.tracer.startSpan(
            spanName,
            context: ServiceContext.topLevel,
            ofKind: .server
        )

        span.attributes["http.method"] = conn.request.method.rawValue
        if let url = conn.request.url {
            span.attributes["http.url"] = url.absoluteString
        }
        if let path = conn.request.path {
            span.attributes["http.target"] = path
        }
        span.attributes["roost.request_id"] = requestId

        return initial.registerBeforeSend { c in
            var result = c
            result.response.headerFields[.xRequestID] = requestId

            // Reflect incoming traceparent for correlation
            if let traceparent = c.request.headerFields[.traceparent] {
                result.response.headerFields[.traceparent] = traceparent
            }

            span.attributes["http.status_code"] = c.response.status.code
            span.end()
            return result
        }
    }
}

// MARK: - HTTP header helpers

extension HTTPField.Name {
    static let traceparent = Self("traceparent")!
    static let tracestate = Self("tracestate")!
    static let xRequestID = Self("X-Request-ID")!
}
