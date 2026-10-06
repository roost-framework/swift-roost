import Foundation
import HTTPTypes
import Nexus

// MARK: - ServerSentEvent

/// A single Server-Sent Event with optional `event:` type, `id:` field, and `data:` payload.
public struct ServerSentEvent: Sendable {
    /// The SSE `event:` field (event type). `nil` produces no `event:` line.
    public let event: String?
    /// The SSE `id:` field (last-event-id for reconnection). `nil` produces no `id:` line.
    public let id: String?
    /// The SSE `data:` field. Typically a JSON-encoded string.
    public let data: String

    public init(event: String? = nil, id: String? = nil, data: String) {
        self.event = event
        self.id    = id
        self.data  = data
    }

    // MARK: - Wire format

    /// Encodes the event to SSE wire format (UTF-8).
    var wireBytes: Data {
        var lines: [String] = []
        if let type = event { lines.append("event: \(type)") }
        if let id            { lines.append("id: \(id)") }
        lines.append("data: \(data)")
        lines.append("")   // empty line terminates the event
        let text = lines.joined(separator: "\n") + "\n"
        return text.data(using: .utf8) ?? Data()
    }

    // MARK: - Parsing (for tests)

    /// Parses a single SSE event from a raw UTF-8 chunk.
    /// Returns `nil` when the chunk contains no `data:` line.
    public static func parse(_ chunk: Data) -> ServerSentEvent? {
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }

        var eventType: String?
        var eventID:   String?
        var dataLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("event: ") {
                eventType = String(line.dropFirst("event: ".count))
            } else if line.hasPrefix("id: ") {
                eventID = String(line.dropFirst("id: ".count))
            } else if line.hasPrefix("data: ") {
                dataLines.append(String(line.dropFirst("data: ".count)))
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(event: eventType, id: eventID, data: dataLines.joined(separator: "\n"))
    }

    // MARK: - Data decoding (for tests)

    /// Decodes the `data` field as the given `Decodable` type.
    public func decodeData<T: Decodable>(_ type: T.Type) throws -> T {
        guard let d = data.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "SSE data field is not valid UTF-8")
            )
        }
        return try JSONDecoder().decode(type, from: d)
    }
}

// MARK: - Connection extensions

extension Connection {

    // MARK: conn.sse(_:)

    /// Returns a streaming SSE response from `stream`.
    ///
    /// Sets `Content-Type: text/event-stream`, `Cache-Control: no-cache`, and
    /// `X-Accel-Buffering: no` (disables nginx proxy buffering).
    /// Halts the connection so downstream plugs are skipped.
    public func sse(_ stream: AsyncStream<ServerSentEvent>) -> Connection {
        let bodyStream = AsyncThrowingStream<Data, any Error> { continuation in
            let task = Task {
                for await event in stream {
                    continuation.yield(event.wireBytes)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return self
            .respond(status: .ok, body: .stream(bodyStream))
            .putRespHeader(.contentType, "text/event-stream")
            .putRespHeader(.cacheControl, "no-cache")
            .putRespHeader("X-Accel-Buffering", "no")
    }

    // MARK: conn.sseStream(from:)

    /// Subscribes to `broadcaster` and returns an `AsyncStream<ServerSentEvent>`.
    ///
    /// - Parameters:
    ///   - broadcaster: The `SSEBroadcaster<T>` to subscribe to.
    ///   - filter: Optional predicate — only matching values become events.
    ///   - eventType: Maps each value to an SSE `event:` field. Returning `nil` omits the field.
    ///   - id: Maps each value to an SSE `id:` field. Returning `nil` omits the field.
    public func sseStream<T: Codable & Sendable>(
        from broadcaster: SSEBroadcaster<T>,
        filter: @Sendable @escaping (T) -> Bool = { _ in true },
        eventType: (@Sendable (T) -> String?)? = nil,
        id: (@Sendable (T) -> String?)? = nil
    ) async -> AsyncStream<ServerSentEvent> {
        let rawStream = await broadcaster.makeStream()
        let (sseStream, continuation) = AsyncStream<ServerSentEvent>.makeStream()
        let encoder = JSONEncoder()

        let task = Task {
            for await value in rawStream {
                guard filter(value) else { continue }
                let dataString: String
                if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
                    dataString = str
                } else {
                    dataString = "{}"
                }
                let sse = ServerSentEvent(
                    event: eventType?(value),
                    id: id?(value),
                    data: dataString
                )
                continuation.yield(sse)
            }
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return sseStream
    }
}
