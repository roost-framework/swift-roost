import Foundation
import HTTPTypes
import Nexus

/// The development endpoint streaming live reload events.
let liveReloadPath = "/_roost/live-reload"

/// Wraps the application with development live reload. Outside `dev` it
/// returns `app` unchanged.
///
/// `GET /_roost/live-reload` streams Server-Sent Events: `boot` with this
/// process's ID on connect, then `css` with a path relative to `Public/`
/// whenever a stylesheet there changes. HTML responses get a script that
/// swaps changed stylesheets in place and reloads the page once a restarted
/// server reports a different boot ID.
///
/// It runs outside the plug pipeline, so the endpoint skips sessions and
/// request logging, and the script is added before `beforeSend` hooks such as
/// `compress()` encode the body.
package func roost_liveReload(_ app: @escaping Plug) -> Plug {
    guard Roost.env == .dev else { return app }
    return { conn in
        if conn.request.method == .get, conn.requestPath == liveReloadPath {
            return conn.sse(await LiveReloadHub.shared.subscribe())
        }
        return injectLiveReloadScript(try await app(conn))
    }
}

/// Adds the live reload script to a buffered, unencoded HTML response,
/// before `</body>` or at the end. HEAD requests and other bodies pass through.
func injectLiveReloadScript(_ conn: Connection) -> Connection {
    guard conn.request.method != .head,
        conn.response.headerFields[.contentType]?.lowercased().hasPrefix("text/html") == true,
        conn.response.headerFields[.contentEncoding] == nil,
        case .buffered(let data) = conn.responseBody,
        var html = String(data: data, encoding: .utf8)
    else { return conn }

    if let end = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
        html.insert(contentsOf: liveReloadScript, at: end.lowerBound)
    } else {
        html += liveReloadScript
    }
    var copy = conn
    copy.responseBody = .buffered(Data(html.utf8))
    copy.response.headerFields[.contentLength] = nil
    return copy
}

/// Streams live reload events to connected browsers, watching `Public/` only
/// while at least one is connected.
actor LiveReloadHub {
    static let shared = LiveReloadHub(directory: "Public")

    /// Differs on every start, so a reconnecting browser can tell the server restarted.
    nonisolated let bootID = UUID().uuidString
    private let directory: String
    private var clients: [UUID: AsyncStream<ServerSentEvent>.Continuation] = [:]
    private var watcher: Task<Void, Never>?
    // Dispatch sources are not Sendable on Linux. They are only changed inside
    // the actor and cancelled in deinit, when nothing else can reach the hub.
    nonisolated(unsafe) private(set) var shutdownSignals: [any DispatchSourceSignal] = []

    init(directory: String) {
        self.directory = directory
    }

    deinit {
        for source in shutdownSignals { source.cancel() }
    }

    func subscribe() -> AsyncStream<ServerSentEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ServerSentEvent>.makeStream()
        continuation.yield(ServerSentEvent(event: "boot", data: bootID))
        continuation.onTermination = { @Sendable _ in
            Task { await self.remove(id) }
        }
        clients[id] = continuation
        if watcher == nil {
            watcher = Task { await watch() }
        }
        // Graceful shutdown waits for open responses, so end the streams on the
        // signals `RoostApp.main()` shuts down on. The disposition is unchanged.
        // This is a fallback: withGracefulShutdownHandler would be cleaner, but
        // needs swift-service-lifecycle declared in Package.swift.
        if shutdownSignals.isEmpty {
            shutdownSignals = [SIGTERM, SIGINT].map { signal in
                let source = DispatchSource.makeSignalSource(signal: signal)
                source.setEventHandler { @Sendable [weak self] in Task { await self?.disconnectAll() } }
                source.resume()
                return source
            }
        }
        return stream
    }

    private func remove(_ id: UUID) {
        clients[id] = nil
        if clients.isEmpty {
            watcher?.cancel()
            watcher = nil
        }
    }

    private func disconnectAll() {
        for client in clients.values { client.finish() }
    }

    private func watch() async {
        var detector = CSSChangeDetector(directory: directory)
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            ticks += 1
            var events = detector.changes().map { ServerSentEvent(event: "css", data: $0) }
            // A closed tab is only noticed on a write, so ping every 15 seconds.
            if ticks.isMultiple(of: 50) {
                events.append(ServerSentEvent(event: "ping", data: ""))
            }
            for event in events {
                for client in clients.values { client.yield(event) }
            }
        }
    }
}

/// Reports `.css` files under a directory whose modification time changed
/// since the previous call.
struct CSSChangeDetector {
    let directory: String
    private var modified: [String: Date]

    init(directory: String) {
        self.directory = directory
        self.modified = Self.scan(directory)
    }

    /// Changed or new stylesheets, as paths relative to `directory`.
    mutating func changes() -> [String] {
        let current = Self.scan(directory)
        defer { modified = current }
        return current.filter { modified[$0.key] != $0.value }.map(\.key).sorted()
    }

    private static func scan(_ directory: String) -> [String: Date] {
        guard let files = FileManager.default.enumerator(atPath: directory) else { return [:] }
        var result: [String: Date] = [:]
        for case let path as String in files where path.hasSuffix(".css") {
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory + "/" + path)
            result[path] = attributes?[.modificationDate] as? Date
        }
        return result
    }
}

/// Keeps the page in sync with the development server. Without EventSource it does nothing.
private let liveReloadScript = """
    <script>(() => {
      if (!window.EventSource) return;
      let boot;
      const connect = () => {
        const source = new EventSource("\(liveReloadPath)");
        source.addEventListener("boot", (event) => {
          if (boot && boot !== event.data) { source.close(); location.reload(); }
          boot = event.data;
        });
        source.addEventListener("css", (event) => {
          const links = [...document.querySelectorAll('link[rel="stylesheet"]')].filter((link) =>
            !link.roostReplacing && new URL(link.href, location.href).origin === location.origin);
          const changed = links.filter((link) =>
            new URL(link.href, location.href).pathname.endsWith("/" + event.data));
          for (const link of changed.length ? changed : links) {
            const fresh = link.cloneNode();
            const url = new URL(link.href, location.href);
            url.searchParams.set("roost-reload", Date.now());
            fresh.href = url;
            link.roostReplacing = true;
            fresh.onload = () => link.remove();
            fresh.onerror = () => { fresh.remove(); link.roostReplacing = false; };
            link.after(fresh);
          }
        });
        source.onerror = () => {
          if (source.readyState === EventSource.CLOSED) setTimeout(connect, 1000);
        };
      };
      connect();
    })();</script>
    """
