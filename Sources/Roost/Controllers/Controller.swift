import Foundation
import HTTPTypes
import Nexus
import NexusRouter

// MARK: - Controller

/// The actions a controller exposes. Raw values name the action in logs and traces.
///
/// ```swift
/// enum Action: String, ControllerAction { case index, show, publish }
/// ```
public protocol ControllerAction: RawRepresentable, CaseIterable, Hashable, Sendable
where RawValue == String {}

/// A group of request handlers, like a Phoenix controller.
///
/// Routes name a controller action instead of holding a closure, so the router
/// reads as a table of the app's endpoints. Each request records the controller
/// and action it ran, which ``roost_requestLogger(filterParameters:logger:)`` and
/// ``tracing(tracer:)`` report.
///
/// ```swift
/// struct RecipeController: Controller {
///     enum Action: String, ControllerAction { case index, show, publish }
///
///     // plug :require_auth when action in [:publish]
///     static let plugs: [ActionPlug<Action>] = [
///         .plug(requireAuth(), only: [.publish]),
///     ]
///
///     static func action(_ action: Action) -> Plug {
///         switch action {
///         case .index: index
///         case .show: show
///         case .publish: publish
///         }
///     }
///
///     static func index(_ conn: Connection) async throws -> Connection { ... }
///     static func show(_ conn: Connection) async throws -> Connection { ... }
///     static func publish(_ conn: Connection) async throws -> Connection { ... }
/// }
///
/// @RouteBuilder var routes: [Route] {
///     resources("/recipes", RecipeController.self, only: [.index, .show])
///     POST("/recipes/:id/publish", RecipeController.self, .publish)
/// }
/// ```
///
/// The compiler checks every name: a route can only name a case of `Action`,
/// and the exhaustive `switch` rejects an action without a function.
public protocol Controller {
    associatedtype Action: ControllerAction

    /// Plugs that run after routing and before the action. Each applies to every
    /// action unless limited with `only:` or `except:`. Default: none.
    static var plugs: [ActionPlug<Action>] { get }

    /// Returns the function that handles `action`. Write it as an exhaustive
    /// `switch`, so adding an action without a function fails to compile.
    static func action(_ action: Action) -> Plug
}

extension Controller {
    public static var plugs: [ActionPlug<Action>] { [] }

    /// The plug a route runs: matching controller plugs, then the action.
    /// The controller and action are recorded before either runs, so they are
    /// reported even when a plug halts or the action throws.
    static func roost_handler(for action: Action) -> Plug {
        let controller = String(describing: Self.self)
        let name = action.rawValue
        let handler = pipeline(plugs.filter { $0.applies(action) }.map(\.plug) + [Self.action(action)])
        return { conn in
            conn[MatchedRouteKey.self]?.update {
                $0.controller = controller
                $0.action = name
            }
            guard let trace = conn[RequestTraceKey.self] else { return try await handler(conn) }
            return try await trace.child(
                "\(controller).\(name)",
                attributes: ["roost.controller": controller, "roost.action": name]
            ) { try await handler(conn) }
        }
    }
}

/// A controller plug, optionally limited to some actions, like Phoenix's
/// `plug :authorize when action in [:edit, :update]`.
///
/// ```swift
/// static let plugs: [ActionPlug<Action>] = [
///     .plug(requireAuth()),
///     .plug(loadRecipe, only: [.show, .edit, .update, .delete]),
///     .plug(requireOwner, except: [.index, .show]),
/// ]
/// ```
public struct ActionPlug<Action: ControllerAction>: Sendable {
    let plug: Plug
    let applies: @Sendable (Action) -> Bool

    /// Runs `plug` before every action.
    public static func plug(_ plug: @escaping Plug) -> Self {
        Self(plug: plug) { _ in true }
    }

    /// Runs `plug` only before the listed actions.
    public static func plug(_ plug: @escaping Plug, only actions: Set<Action>) -> Self {
        Self(plug: plug) { actions.contains($0) }
    }

    /// Runs `plug` before every action except the listed ones.
    public static func plug(_ plug: @escaping Plug, except actions: Set<Action>) -> Self {
        Self(plug: plug) { !actions.contains($0) }
    }
}

// MARK: - Routes to actions

/// A GET route handled by a controller action.
public func GET<C: Controller>(_ path: String, _ controller: C.Type, _ action: C.Action) -> Route {
    Route(method: .get, path: path, handler: C.roost_handler(for: action))
}

/// A POST route handled by a controller action.
public func POST<C: Controller>(_ path: String, _ controller: C.Type, _ action: C.Action) -> Route {
    Route(method: .post, path: path, handler: C.roost_handler(for: action))
}

/// A PUT route handled by a controller action.
public func PUT<C: Controller>(_ path: String, _ controller: C.Type, _ action: C.Action) -> Route {
    Route(method: .put, path: path, handler: C.roost_handler(for: action))
}

/// A PATCH route handled by a controller action.
public func PATCH<C: Controller>(_ path: String, _ controller: C.Type, _ action: C.Action) -> Route {
    Route(method: .patch, path: path, handler: C.roost_handler(for: action))
}

/// A DELETE route handled by a controller action.
public func DELETE<C: Controller>(_ path: String, _ controller: C.Type, _ action: C.Action) -> Route {
    Route(method: .delete, path: path, handler: C.roost_handler(for: action))
}

/// The REST actions ``resources(_:_:only:except:)`` routes, in matching order.
/// `new` comes before `show` so `/recipes/new` is not read as an id.
private let restRoutes: [(action: String, method: HTTPRequest.Method, suffix: String)] = [
    ("index", .get, ""),
    ("new", .get, "/new"),
    ("create", .post, ""),
    ("show", .get, "/:id"),
    ("edit", .get, "/:id/edit"),
    ("update", .patch, "/:id"),
    ("update", .put, "/:id"),
    ("delete", .delete, "/:id"),
]

/// REST routes for a controller, like Phoenix's `resources`.
///
/// | Action   | Route                                      |
/// |----------|--------------------------------------------|
/// | `index`  | `GET /recipes`                             |
/// | `new`    | `GET /recipes/new`                         |
/// | `create` | `POST /recipes`                            |
/// | `show`   | `GET /recipes/:id`                         |
/// | `edit`   | `GET /recipes/:id/edit`                    |
/// | `update` | `PATCH /recipes/:id` and `PUT /recipes/:id` |
/// | `delete` | `DELETE /recipes/:id`                      |
///
/// Only the REST actions the controller declares are routed, narrowed further
/// by `only:` or `except:`. Route other actions with ``GET(_:_:_:)`` and the
/// other verb functions.
///
/// ```swift
/// resources("/recipes", RecipeController.self)
/// resources("/comments", CommentController.self, only: [.create, .delete])
/// ```
///
/// - Precondition: `only:` and `except:` are not combined, and `only:` names
///   REST actions. Routes are built at startup, so a mistake stops the app
///   before it serves requests.
public func resources<C: Controller>(
    _ path: String,
    _ controller: C.Type,
    only: Set<C.Action>? = nil,
    except: Set<C.Action> = []
) -> [Route] {
    precondition(only == nil || except.isEmpty,
                 "resources(\"\(path)\", \(C.self).self) takes only: or except:, not both.")
    let rest = Set(restRoutes.map(\.action))
    if let extra = only?.first(where: { !rest.contains($0.rawValue) }) {
        preconditionFailure("""
            resources(\"\(path)\", \(C.self).self) can't route .\(extra.rawValue): it is not a REST action. \
            Route it with GET, POST, PUT, PATCH or DELETE instead.
            """)
    }
    let base = path.hasSuffix("/") ? String(path.dropLast()) : path
    return restRoutes.compactMap { route in
        guard let action = C.Action(rawValue: route.action),
              only?.contains(action) ?? true,
              !except.contains(action) else { return nil }
        let suffix = base.isEmpty && route.suffix.isEmpty ? "/" : route.suffix
        return Route(method: route.method, path: base + suffix, handler: C.roost_handler(for: action))
    }
}
