import Foundation

/// The runtime environment for a Roost application.
public enum Environment: String, Sendable {
    case dev
    case test
    case prod
}

/// Top-level Roost namespace.
public enum Roost {
    /// Task-local override used by in-process tests; does not mutate process globals.
    @TaskLocal public static var environmentOverride: Environment?

    public static var env: Environment { environmentOverride ?? processEnvironment }

    /// Current environment, read once at startup from the `ROOST_ENV`
    /// environment variable. Defaults to `.dev` when unset or unrecognized.
    private static let processEnvironment: Environment = {
        guard let raw = ProcessInfo.processInfo.environment["ROOST_ENV"] else {
            return .dev
        }
        return Environment(rawValue: raw) ?? .dev
    }()
}
