import Foundation
import Nexus

// MARK: - Flash Types

/// The severity level of a flash message.
///
/// Flash messages are one-time notifications displayed to the user on the
/// next request. Each level maps to a distinct UI treatment (colour, icon, etc.).
public enum FlashLevel: String, Sendable {
    case info
    case error
    case warning
}

/// A container for flash messages read from the session.
///
/// At most one message per level is stored. After the flash is read by the
/// ``flashPlug()`` plug it is cleared from the session, ensuring each message
/// is displayed exactly once (the "flash" pattern).
public struct Flash: Sendable {
    public var info: String?
    public var error: String?
    public var warning: String?

    public init(info: String? = nil, error: String? = nil, warning: String? = nil) {
        self.info = info
        self.error = error
        self.warning = warning
    }

    /// Returns `true` when no messages are set at any level.
    public var isEmpty: Bool {
        info == nil && error == nil && warning == nil
    }
}

// MARK: - Typed Assign Keys

/// Typed assign key for the current request's flash messages.
///
/// Populated by ``flashPlug()`` from session data and accessible via
/// `conn[FlashKey.self]` or the convenience `conn.flash` property.
public enum FlashKey: AssignKey {
    public typealias Value = Flash
}

/// Typed assign key for flash messages queued by ``Nexus/Connection/putFlash(_:_:)``
/// during the current request, to be written to the session before the
/// response is sent.
public enum PendingFlashKey: AssignKey {
    public typealias Value = [String: String]
}

// MARK: - Connection Extensions

extension Connection {

    /// Queues a flash message to be written to the session before the response
    /// is sent.
    ///
    /// The message is stored under ``PendingFlashKey`` in assigns and written
    /// immediately to the `_flash` session key. The request finalizer awaits
    /// persistence before sending the response. If the same level is written multiple times, the last write
    /// wins.
    ///
    /// ```swift
    /// conn.putFlash(.info, "Item created successfully")
    /// ```
    ///
    /// - Parameters:
    ///   - level: The severity level of the message.
    ///   - message: The human-readable message text.
    /// - Returns: A new connection with the pending flash updated.
    public func putFlash(_ level: FlashLevel, _ message: String) -> Connection {
        var pending = self[PendingFlashKey.self] ?? [:]
        pending[level.rawValue] = message
        let conn = assign(PendingFlashKey.self, value: pending)
        guard let data = try? JSONEncoder().encode(pending),
              let json = String(data: data, encoding: .utf8) else { return conn }
        // Update immediately so the awaited request finalizer persists flash
        // before emitting a redirect or invoking response hooks.
        return conn.putSession(key: "_flash", value: json)
    }

    /// The flash messages for the current request, populated by ``flashPlug()``.
    ///
    /// Returns an empty ``Flash`` when no messages were set on the previous
    /// request or when ``flashPlug()`` has not run.
    public var flash: Flash {
        self[FlashKey.self] ?? Flash()
    }
}

// MARK: - Flash Plug

/// A plug that manages one-time flash messages via the session.
///
/// Flash messages are set with ``Nexus/Connection/putFlash(_:_:)`` during a
/// request and stored in the session under the `_flash` key. On the next
/// request, this plug reads those messages into ``FlashKey`` assigns (and
/// the string key `"flash"` for template engines), then clears them from
/// the session so they display exactly once.
///
/// This plug must run **after** the session plug in the pipeline, since it
/// reads and writes session data.
///
/// ```swift
/// var plugs: [Plug] {
///     [
///         sessionPlug(sessionConfig),
///         flashPlug(),
///         requestLogger(),
///     ]
/// }
/// ```
///
/// - Returns: A plug that manages flash messages.
public func flashPlug() -> Plug {
    { conn in
        // --- Read phase: pull flash from session ---
        let flashJSON = conn.getSession("_flash")
        var flash = Flash()

        if let json = flashJSON,
           let data = json.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data)
        {
            flash.info = dict["info"]
            flash.error = dict["error"]
            flash.warning = dict["warning"]
        }

        // Inject flash into assigns — typed key for code, string key for templates
        var result = conn
            .assign(FlashKey.self, value: flash)
            .assign(key: "flash", value: flash)

        // Clear flash from session after reading so it displays exactly once
        if flashJSON != nil {
            result = result.deleteSession("_flash")
        }

        return result
    }
}
