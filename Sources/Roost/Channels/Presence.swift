import Foundation

// MARK: - PresenceEntry

/// One entry in the presence list — a single user/key with one or more metas.
///
/// Multiple metas occur when the same user joins from multiple browser tabs.
public struct PresenceEntry: Sendable {
    /// Typically the user's UUID string — uniquely identifies who is present.
    public let key: String
    /// One metadata dict per joined socket for this key.
    public let metas: [[String: any Sendable]]
}

// MARK: - Presence

/// Tracks which sockets are currently online per topic.
///
/// Backed by `ChannelRegistry`'s in-memory presence state.
/// Automatically broadcasts `presence_diff` events to all other subscribers
/// when a socket joins or leaves.
///
/// ```swift
/// // In Channel.join:
/// try await Presence.track(socket, topic: topic, key: userID.uuidString, meta: [
///     "name": userName, "online_at": Date().timeIntervalSince1970
/// ])
/// let current = await Presence.list(topic, socket: socket)
/// return ["status": "ok", "presence": current as any Sendable]
///
/// // In Channel.leave:
/// await Presence.untrack(socket, topic: topic, key: userID.uuidString)
/// ```
public enum Presence {

    // MARK: - Track

    /// Registers a socket's presence on a topic with the given key and metadata.
    /// Broadcasts a `presence_diff` joins event to all **other** subscribers.
    public static func track(
        _ socket: ChannelSocket,
        topic: String,
        key: String,
        meta: ChannelPayload
    ) async throws {
        guard let registry = socket.registry else { return }
        registry.trackPresence(socketID: socket.id, topic: topic, key: key, meta: meta)
        // Broadcast join diff to all others (exclude the joiner)
        let joinsDict: [String: String] = [key: meta["name"] as? String ?? key]
        let emptyLeaves: [String: String] = [:]
        try await registry.deliver(
            topic: topic,
            event: "presence_diff",
            payload: ["joins": joinsDict as any Sendable, "leaves": emptyLeaves as any Sendable],
            from: socket,
            excludeSender: true
        )
    }

    // MARK: - Untrack

    /// Removes a socket's presence entry for the given key on a topic.
    /// Broadcasts a `presence_diff` leaves event to all remaining subscribers.
    public static func untrack(
        _ socket: ChannelSocket,
        topic: String,
        key: String
    ) async {
        guard let registry = socket.registry else { return }
        // Capture meta BEFORE removing (for the diff payload)
        let meta = registry.presenceMeta(socketID: socket.id, topic: topic, key: key)
        registry.untrackPresence(socketID: socket.id, topic: topic, key: key)
        // Broadcast leave diff to all others (exclude the leaver)
        let leavesDict: [String: String] = [key: meta?["name"] as? String ?? key]
        let emptyJoins: [String: String] = [:]
        try? await registry.deliver(
            topic: topic,
            event: "presence_diff",
            payload: ["joins": emptyJoins as any Sendable, "leaves": leavesDict as any Sendable],
            from: socket,
            excludeSender: true
        )
    }

    // MARK: - List

    /// Returns the current presence list for a topic.
    /// Entries are sorted by the earliest `online_at` value across all metas.
    public static func list(_ topic: String, socket: ChannelSocket) async -> [PresenceEntry] {
        socket.registry?.listPresence(topic: topic) ?? []
    }

    /// Returns the current presence list for a topic using a registry directly.
    public static func list(_ topic: String, registry: ChannelRegistry) -> [PresenceEntry] {
        registry.listPresence(topic: topic)
    }
}
