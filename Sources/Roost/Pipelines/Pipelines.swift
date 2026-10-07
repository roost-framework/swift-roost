import Foundation
import Nexus
import NexusRouter

// MARK: - DSL: scope(prefix:pipelines:) { routes }

/// Creates a group of routes sharing a path prefix and one or more pipelines.
///
/// A pipeline is a plain value, so routers split across files share it by
/// name in Swift, and a typo is a compile error:
///
/// ```swift
/// let browser = NamedPipeline { browserPlugs() }
/// let authenticated = NamedPipeline { requireAuth() }
///
/// @RouteBuilder func accountRoutes() -> [Route] {
///     scope("/", pipelines: [browser, authenticated]) {
///         GET("/dashboard", DashboardController.self, .index)
///         resources("/recipes", RecipeController.self)
///     }
/// }
/// ```
///
/// Pipelines run left to right: the first one in the array runs first.
///
/// - Parameters:
///   - prefix: Path prefix to prepend to all nested routes.
///   - pipelines: The pipelines to apply, in order.
///   - build: A `@RouteBuilder` closure that declares the routes in this scope.
/// - Returns: Routes with the prefix and pipeline plugs applied.
public func scope(
    _ prefix: String,
    pipelines: [NamedPipeline],
    @RouteBuilder _ build: () -> [Route]
) -> [Route] {
    scope(prefix, through: pipelines.map { $0.asPlug() }, build)
}

extension PlugPipeline {
    /// Accepts a list of plugs, such as `browserPlugs()`, inside a pipeline builder.
    public static func buildExpression(_ plugs: [Plug]) -> [Plug] {
        plugs
    }
}

// MARK: - DSL: scope(prefix:plugs:) { routes } — inline anonymous pipeline

/// Creates a group of routes sharing a path prefix and an inline list of plugs.
///
/// Use this for one-off middleware needs that don't warrant a named pipeline.
///
/// ```swift
/// scope("/admin", plugs: [requireRole("admin")]) {
///     GET("/users", AdminController.self, .users)
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

// MARK: - Deprecated string pipelines

/// Storage for the deprecated string pipelines, written while `routes` is evaluated.
nonisolated(unsafe) private var _pipelineRegistry: [String: [Plug]] = [:]

/// Declares a pipeline by name inside a `@RouteBuilder` closure.
///
/// Deprecated: names live in global state, so a scope works only when the
/// declaration was evaluated first, which breaks when routers are split across
/// files. Declare a `NamedPipeline` value and pass it to `scope(_:pipelines:)`.
@available(*, deprecated, message: "Declare a NamedPipeline value and pass it to scope(_:pipelines:) instead.")
@discardableResult
public func pipeline(_ name: String, @PlugPipeline _ build: () -> [Plug]) -> [Route] {
    _pipelineRegistry[name] = build()
    return []
}

/// Applies pipelines declared with the deprecated `pipeline(_:_:)` by name.
///
/// - Precondition: Every name was declared before this scope is evaluated.
///   An unknown name stops the app at startup instead of serving the routes
///   without the pipeline's plugs, such as CSRF protection or authentication.
@available(*, deprecated, message: "Declare a NamedPipeline value and pass it to scope(_:pipelines:) instead.")
public func scope(
    _ prefix: String,
    pipelines names: [String],
    @RouteBuilder _ build: () -> [Route]
) -> [Route] {
    let plugs = names.flatMap { name -> [Plug] in
        guard let plugs = _pipelineRegistry[name] else {
            preconditionFailure("""
                scope(\"\(prefix)\") uses pipeline \"\(name)\", which was not declared before it. \
                Declare it with pipeline(\"\(name)\") earlier, or use a NamedPipeline value.
                """)
        }
        return plugs
    }
    return scope(prefix, through: plugs, build)
}
