import Nexus

/// Typed assign key for injecting the PubSub adapter into the connection pipeline.
public enum PubSubKey: AssignKey {
    public typealias Value = any RoostPubSub
}

extension Connection {
    /// The PubSub adapter injected by Roost's bootstrap.
    /// Available in route handlers when `pubSub` is configured on the app.
    public var pubSub: any RoostPubSub {
        guard let adapter = self[PubSubKey.self] else {
            fatalError("No PubSub configured. Set `pubSub` in your RoostApp.")
        }
        return adapter
    }
}
