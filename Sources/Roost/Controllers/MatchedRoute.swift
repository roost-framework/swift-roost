import Foundation
import Nexus
import NexusRouter

/// The endpoint a request matched: its route pattern and, for controller
/// routes, the controller and action.
///
/// Routing records it, and it stays available on error responses, so request
/// logs, traces and metrics can name the endpoint once the response is ready.
public struct MatchedRoute: Sendable, Equatable {
    /// The route pattern, such as `/recipes/:id`.
    public var pattern: String?
    /// The controller type, such as `RecipeController`.
    public var controller: String?
    /// The action, such as `show`.
    public var action: String?
    /// The path parameters the route captured.
    public var pathParams: [String: String] = [:]

    public init() {}
}

/// One per request. A reference, so plugs that ran before the router read what
/// routing recorded, including after an error replaced the connection.
final class MatchedRouteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = MatchedRoute()

    var route: MatchedRoute { lock.withLock { value } }

    func update(_ change: (inout MatchedRoute) -> Void) {
        lock.withLock { change(&value) }
    }
}

enum MatchedRouteKey: AssignKey {
    typealias Value = MatchedRouteRecorder
}

extension Connection {
    /// The endpoint this request matched. Empty before routing or when no route matched.
    public var matchedRoute: MatchedRoute {
        self[MatchedRouteKey.self]?.route ?? MatchedRoute()
    }

    /// Adds a recorder for routing to fill in, unless an earlier plug did.
    func roost_recordingMatchedRoute() -> Connection {
        self[MatchedRouteKey.self] == nil ? assign(MatchedRouteKey.self, value: MatchedRouteRecorder()) : self
    }
}

/// Records each route's pattern and path parameters when it matches, before its handler runs.
func roost_recordingMatches(_ routes: [Route]) -> [Route] {
    routes.map { route in
        let pattern = route.path
        let handler = route.handler
        return Route(method: route.method, path: pattern) { conn in
            conn[MatchedRouteKey.self]?.update {
                $0.pattern = pattern
                $0.pathParams = conn.params
            }
            return try await handler(conn)
        }
    }
}
