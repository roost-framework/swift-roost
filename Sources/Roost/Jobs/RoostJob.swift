import Foundation
import Spectro

// MARK: - RetryStrategy

/// Determines how many times a failing job is retried before being discarded.
public enum RetryStrategy: Sendable {
    /// No retries — the job runs once and is discarded on failure.
    case none
    /// Retry with exponential back-off (in-memory driver retries inline in tests).
    case exponentialJitter(maxAttempts: Int)

    var maxAttempts: Int {
        switch self {
        case .none:                        return 1
        case .exponentialJitter(let n):    return n
        }
    }
}

// MARK: - JobContext

/// Passed to every executing job. Provides access to framework services.
public struct JobContext: Sendable {
    /// Database client, or `nil` when running without a database.
    public let spectro: SpectroClient?
    /// The job queue — use this to enqueue follow-up jobs from within a job.
    public let queue: any RoostJobQueue
    /// App-specific services for test fixtures and middleware (e.g. mock mailer).
    public let userInfo: [String: any Sendable]

    public init(
        spectro: SpectroClient? = nil,
        queue: any RoostJobQueue,
        userInfo: [String: any Sendable] = [:]
    ) {
        self.spectro = spectro
        self.queue = queue
        self.userInfo = userInfo
    }
}

// MARK: - RoostJob

/// A unit of background work with typed, Codable parameters.
///
/// ```swift
/// struct WelcomeEmailJob: RoostJob {
///     struct Parameters: Codable, Sendable {
///         let userID: UUID
///         let email: String
///     }
///
///     static var retryStrategy: RetryStrategy { .exponentialJitter(maxAttempts: 3) }
///
///     func execute(parameters: Parameters, context: JobContext) async throws {
///         // send email…
///     }
/// }
/// ```
public protocol RoostJob: Sendable {
    associatedtype Parameters: Codable & Sendable

    init()

    /// How many times the job is retried before being discarded. Default: `.none`.
    static var retryStrategy: RetryStrategy { get }

    /// Per-execution timeout. Default: 30 seconds.
    static var timeout: Duration { get }

    func execute(parameters: Parameters, context: JobContext) async throws
}

public extension RoostJob {
    static var retryStrategy: RetryStrategy { .none }
    static var timeout: Duration { .seconds(30) }
    static var name: String { String(describing: Self.self) }
}
