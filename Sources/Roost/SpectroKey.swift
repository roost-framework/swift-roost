import Nexus
import Spectro

/// Typed assign key for the SpectroClient in the connection pipeline.
public enum SpectroKey: AssignKey {
    public typealias Value = SpectroClient
}

/// Override the repository, for example with a transaction-owned repository in tests.
public enum RepositoryKey: AssignKey {
    public typealias Value = any Repo
}

extension Connection {
    /// The SpectroClient injected by Roost's bootstrap.
    /// Available in route handlers when `database` is configured.
    public var spectro: SpectroClient {
        guard let client = self[SpectroKey.self] else {
            fatalError("No database configured. Set `database` in your RoostApp.")
        }
        return client
    }

    /// Use the injected repository, or create one from the configured SpectroClient.
    public func repo() -> any Repo {
        if let repository = self[RepositoryKey.self] { return repository }
        return spectro.repository()
    }
}
