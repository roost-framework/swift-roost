import Foundation
import Nexus
import NexusRouter

// MARK: - Named pipeline registry

/// Thread-unsafe storage used exclusively during synchronous `routes` property evaluation.
///
/// `pipeline(_:_:)` writes here; `scope(_:pipelines:_:)` reads here.
/// Safe because `routes` is always evaluated on one thread at startup.
nonisolated(unsafe) private var _pipelineRegistry: [String: [Plug]] = [:]

// MARK: - DSL: pipeline(name:) { plugs }

/// Declares a named pipeline inside a `@RouteBuilder` closure.
///
/// A pipeline is a reusable, ordered list of plugs. Declare it before any
/// `scope(pipelines:)` that references it — declarations are processed in order.
///
/// ```swift
/// @RouteBuilder var routes: [Route] {
///     pipeline("browser") {
///         bodyParser()
///         flashPlug()
///         roost_csrfProtection()
///     }
///
///     scope("/", pipelines: ["browser"]) {
///         GET("/",      HomeController.index)
///         GET("/login", SessionController.new)
///     }
/// }
/// ```
///
/// - Parameters:
///   - name: A unique identifier for this pipeline (e.g. `"browser"`, `"api"`).
///   - build: A `@PlugPipeline` builder that returns the ordered list of plugs.
/// - Returns: An empty route array (used by `@RouteBuilder` for composition).
@discardableResult
public func pipeline(_ name: String, @PlugPipeline _ build: () -> [Plug]) -> [Route] {
    _pipelineRegistry[name] = build()
    return []
}

// MARK: - DSL: scope(prefix:pipelines:) { routes }

/// Creates a group of routes sharing a path prefix and one or more named pipelines.
///
/// Pipelines are composed left-to-right: the first name in the array runs first.
/// Named pipelines must be declared with `pipeline(_:_:)` before this call.
///
/// ```swift
/// scope("/", pipelines: ["browser", "authenticated"]) {
///     GET("/dashboard", DashboardController.index)
///     GET("/profile",   UserController.show)
/// }
/// ```
///
/// - Parameters:
///   - prefix: Path prefix to prepend to all nested routes.
///   - names: Names of previously declared pipelines to apply, in order.
///   - build: A `@RouteBuilder` closure that declares the routes in this scope.
/// - Returns: Routes with the prefix and pipeline plugs applied.
public func scope(
    _ prefix: String,
    pipelines names: [String],
    @RouteBuilder _ build: () -> [Route]
) -> [Route] {
    let plugs = names.flatMap { _pipelineRegistry[$0] ?? [] }
    return scope(prefix, through: plugs, build)
}

// MARK: - DSL: scope(prefix:plugs:) { routes } — inline anonymous pipeline

/// Creates a group of routes sharing a path prefix and an inline list of plugs.
///
/// Use this for one-off middleware needs that don't warrant a named pipeline.
///
/// ```swift
/// scope("/admin", plugs: [requireRole("admin")]) {
///     GET("/users", AdminController.users)
/// }
/// ```
///
/// - Parameters:
///   - prefix: Path prefix to prepend to all nested routes.
///   - plugs: Ordered list of plugs to apply before each route's handler.
///   - build: A `@RouteBuilder` closure that declares the routes in this scope.
/// - Returns: Routes with the prefix and plugs applied.
public func scope(
    _ prefix: String,
    plugs: [Plug],
    @RouteBuilder _ build: () -> [Route]
) -> [Route] {
    scope(prefix, through: plugs, build)
}
