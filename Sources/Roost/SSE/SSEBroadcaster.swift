import Foundation

/// A fan-out actor that broadcasts values to all current subscribers.
///
/// Each call to `makeStream()` returns an `AsyncStream<T>` that receives
/// every value published after the subscription was created. When the stream
/// is cancelled (e.g. the client disconnects), the subscriber is removed.
///
/// ```swift
/// struct MyApp: RoostApp {
///     static let events = SSEBroadcaster<MyEvent>()
///     ...
/// }
///
/// // In a route handler:
/// let stream = await conn.sseStream(from: MyApp.events)
/// return conn.sse(stream)
///
/// // From anywhere:
/// await MyApp.events.publish(event)
/// ```
public actor SSEBroadcaster<T: Sendable>: Sendable {

    private var continuations: [UUID: AsyncStream<T>.Continuation] = [:]

    public init() {}

    // MARK: - Publishing

    /// Delivers `value` to all current subscribers.
    public func publish(_ value: T) {
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    // MARK: - Subscribing

    /// Creates a new `AsyncStream<T>` and registers it as a subscriber.
    /// The stream is automatically removed when it is cancelled.
    public func makeStream() -> AsyncStream<T> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<T>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { [weak self] in await self?.remove(id: id) }
        }
        return stream
    }

    // MARK: - Test helpers

    /// Suspends until at least `count` subscribers are registered.
    /// Useful in tests to ensure subscriptions are set up before publishing.
    public func waitForSubscribers(atLeast count: Int = 1) async {
        while continuations.count < count {
            await Task.yield()
        }
    }

    /// Returns the current subscriber count.
    public var subscriberCount: Int { continuations.count }

    // MARK: - Internal

    private func remove(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
