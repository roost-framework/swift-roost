import Foundation
import HTTPTypes
import Nexus
import Tracing

// MARK: - Tracing Plug

/// A Nexus plug that creates a distributed tracing span for each request.
///
/// Features:
/// - Continues the caller's trace from incoming `traceparent`/`tracestate`
///   headers when the tracer understands them (for example, OpenTelemetry's)
/// - Names the server span after the matched route, such as
///   `GET /recipes/:id`, so one endpoint is one span name whatever the IDs
/// - Wraps each controller action in a child span named `RecipeController.show`
/// - Records attributes: http.method, http.url, http.target, http.route,
///   http.status_code, roost.request_id, roost.controller, roost.action
/// - Reuses the ID from ``requestId(generator:headerName:)`` when it ran first
///
/// ```swift
/// var plugs: [Plug] {
///     [requestId(), tracing(), roost_requestLogger()]
/// }
/// ```
///
/// - Parameter tracer: The tracer to use. Default: the one bootstrapped in
///   `InstrumentationSystem`, read on each request.
public func tracing(tracer: (any Tracer)? = nil) -> Plug {
    { conn in
        let tracer = tracer ?? InstrumentationSystem.tracer
        var initial = conn.roost_recordingMatchedRoute()
        let requestId = conn.requestId ?? UUID().uuidString
        if conn.requestId == nil {
            initial = initial.assign(RequestIdKey.self, value: requestId).assign(key: "request_id", value: requestId)
        }

        var context = ServiceContext.topLevel
        tracer.extract(conn.request.headerFields, into: &context, using: HTTPFieldsExtractor())

        let method = conn.request.method.rawValue
        let span = tracer.startSpan(method, context: context, ofKind: .server)

        span.attributes["http.method"] = method
        if let url = conn.request.url {
            span.attributes["http.url"] = url.absoluteString
        }
        if let path = conn.request.path {
            span.attributes["http.target"] = path
        }
        span.attributes["roost.request_id"] = requestId
        initial = initial.assign(RequestTraceKey.self, value: RequestTrace(span: span, tracer: tracer))

        return initial.registerBeforeSend { c in
            var result = c
            result.response.headerFields[RoostTracingHeaders.xRequestID] = requestId

            // Reflect incoming traceparent for correlation
            if let traceparent = c.request.headerFields[RoostTracingHeaders.traceparent] {
                result.response.headerFields[RoostTracingHeaders.traceparent] = traceparent
            }

            let route = c.matchedRoute
            if let pattern = route.pattern {
                span.operationName = "\(method) \(pattern)"
                span.attributes["http.route"] = pattern
            }
            if let controller = route.controller, let action = route.action {
                span.attributes["roost.controller"] = controller
                span.attributes["roost.action"] = action
            }
            span.attributes["http.status_code"] = c.response.status.code
            if c.response.status.kind == .serverError {
                span.setStatus(SpanStatus(code: .error))
            }
            span.end()
            return result
        }
    }
}

/// The request's server span and the tracer that started it, so controller
/// actions can start child spans under it.
struct RequestTrace: Sendable {
    let span: any Span
    let tracer: any Tracer

    /// Runs `operation` in a child span that is current for its duration, so
    /// spans started inside it (database queries, HTTP calls) nest under it.
    func child(
        _ name: String,
        attributes: [String: String],
        _ operation: () async throws -> Connection
    ) async throws -> Connection {
        let child = tracer.startSpan(name, context: span.context, ofKind: .internal)
        for (key, value) in attributes {
            child.attributes[key] = value
        }
        defer { child.end() }
        do {
            return try await ServiceContext.withValue(child.context) { try await operation() }
        } catch {
            child.recordError(error)
            child.setStatus(SpanStatus(code: .error))
            throw error
        }
    }
}

enum RequestTraceKey: AssignKey {
    typealias Value = RequestTrace
}

/// Reads W3C trace context headers for the tracer's propagator.
struct HTTPFieldsExtractor: Extractor {
    func extract(key: String, from fields: HTTPFields) -> String? {
        HTTPField.Name(key).flatMap { fields[$0] }
    }
}

// MARK: - HTTP header helpers

// Keep our names out of HTTPTypes' namespace as it adds standard header names.
enum RoostTracingHeaders {
    static let traceparent = HTTPField.Name("traceparent")!
    static let tracestate = HTTPField.Name("tracestate")!
    static let xRequestID = HTTPField.Name("X-Request-ID")!
}
