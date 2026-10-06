import Foundation
import Nexus

// MARK: - AuthScope Protocol

/// A scope carries context about the current authenticated entity and is
/// used for database query scoping, authorization checks, and generator
/// integration.
///
/// **Framework-provided protocol.** Conform your scope types to this:
///
/// ```swift
/// struct UserScope: AuthScope {
///     let userId: String?
///
///     static var scopeName: String { "user" }
///     var scopeId: String? { userId }
/// }
/// ```
///
/// Then store it in the connection:
///
/// ```swift
/// let conn = conn.setScope(UserScope(userId: user.id.uuidString))
///
/// // Later, retrieve it:
/// if let scope = conn.currentScope(UserScope.self) {
///     // query posts WHERE user_id = scope.userId
/// }
/// ```
public protocol AuthScope: Sendable {
    /// Unique name for this scope type (e.g. `"user"`, `"session"`, `"org"`).
    static var scopeName: String { get }

    /// The primary identifying value for this scope (e.g. a user ID).
    /// Returns `nil` when no entity is authenticated.
    var scopeId: String? { get }

    /// `true` when no authenticated entity is present.
    var isEmpty: Bool { get }
}

extension AuthScope {
    public static var scopeName: String { String(describing: Self.self) }
    public var isEmpty: Bool { scopeId == nil }
}

// MARK: - Assign Key

extension AuthAssign {
    /// The currently active scope (type-erased).
    public static let currentScope = "_roost_current_scope"
}

// MARK: - Connection Extensions

extension Connection {

    /// Store a scope in assigns.
    ///
    /// ```swift
    /// conn = conn.setScope(UserScope(userId: user.authID))
    /// ```
    public func setScope<S: AuthScope>(_ scope: S) -> Connection {
        assign(key: AuthAssign.currentScope, value: scope)
    }

    /// Retrieve the current scope, cast to the expected type.
    ///
    /// Returns `nil` if no scope has been set or the type doesn't match.
    ///
    /// ```swift
    /// if let scope = conn.currentScope(UserScope.self) { ... }
    /// ```
    public func currentScope<S: AuthScope>(_ type: S.Type) -> S? {
        assigns[AuthAssign.currentScope] as? S
    }

    /// `true` when a non-empty scope is present.
    public var hasScope: Bool {
        if let scope = assigns[AuthAssign.currentScope] as? (any AuthScope) {
            return !scope.isEmpty
        }
        return false
    }
}

// MARK: - Authorization Protocols

/// Conform your user model to this protocol to enable ``requireRole(_:redirectTo:)``.
///
/// ```swift
/// extension User: UserRoleProvider {
///     var role: String { isAdmin ? "admin" : "user" }
/// }
/// ```
public protocol UserRoleProvider {
    /// The user's role (e.g. `"admin"`, `"moderator"`, `"user"`).
    var role: String { get }
}

/// Conform your user model to this protocol to enable
/// ``requirePermission(_:redirectTo:)``.
///
/// ```swift
/// extension User: PermissionProvider {
///     func hasPermission(_ permission: String) -> Bool {
///         permissions.contains(permission)
///     }
/// }
/// ```
public protocol PermissionProvider {
    /// Check whether the entity has the given permission.
    func hasPermission(_ permission: String) -> Bool
}

// MARK: - Scope Metadata

/// Metadata describing a scope for use by code generators.
///
/// Stored in your app's scope configuration and consumed by
/// `roost gen` to produce scope-aware CRUD scaffolds.
///
/// ```swift
/// let userMeta = ScopeMetadata(
///     name: "user",
///     schemaKey: "user_id",
///     schemaType: "UUID",
///     schemaTable: "users"
/// )
/// ```
public struct ScopeMetadata: Sendable, Equatable {
    /// Scope name (e.g. `"user"`, `"session"`).
    public let name: String

    /// Whether this is the default scope for generators.
    public let isDefault: Bool

    /// The assigns key where the scope is stored.
    public let assignKey: String

    /// Foreign key column name in generated schemas (e.g. `"user_id"`).
    public let schemaKey: String

    /// Foreign key SQL type (e.g. `"UUID"`, `"BIGINT"`).
    public let schemaType: String

    /// Referenced table name (e.g. `"users"`), if any.
    public let schemaTable: String?

    /// Optional route prefix for scoped routes (e.g. `"/orgs/:slug"`).
    public let routePrefix: String?

    public init(
        name: String,
        isDefault: Bool = false,
        assignKey: String = AuthAssign.currentScope,
        schemaKey: String,
        schemaType: String = "UUID",
        schemaTable: String? = nil,
        routePrefix: String? = nil
    ) {
        self.name = name
        self.isDefault = isDefault
        self.assignKey = assignKey
        self.schemaKey = schemaKey
        self.schemaType = schemaType
        self.schemaTable = schemaTable
        self.routePrefix = routePrefix
    }
}
