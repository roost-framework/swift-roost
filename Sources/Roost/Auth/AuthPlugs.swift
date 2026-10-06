import HTTPTypes
import Nexus

// MARK: - requireAuth

/// Require session authentication — redirects unauthenticated users to a login page.
///
/// Place this plug on routes (or scopes) that should only be accessible
/// to logged-in users. When no user is found in assigns, the original
/// request path is saved in the session under `returnToKey` so the login
/// handler can redirect back after a successful sign-in.
///
/// The plug checks ``Nexus/Connection/isAuthenticated`` which is set to `true`
/// when ``Nexus/Connection/setCurrentUser(_:)`` or ``Nexus/Connection/loginUser(_:remember:token:)``
/// has been called earlier in the pipeline.
///
/// ```swift
/// // Typical pipeline: session → fetchUser → router
/// // Protected scope:
/// scope("/dashboard", plugs: [requireAuth()]) {
///     GET("/dashboard") { conn in
///         let user = conn.currentUser(User.self)!
///         // ...
///     }
/// }
/// ```
///
/// - Parameters:
///   - redirectTo: Path to redirect unauthenticated users to (default: `/auth/login`).
///   - returnToKey: Session key for storing the original URL (default: `auth_return_to`).
/// - Returns: A plug that enforces authentication.
public func requireAuth(
    redirectTo: String = "/auth/login",
    returnToKey: String = "auth_return_to"
) -> Plug {
    { conn in
        guard conn.isAuthenticated else {
            // Save original path so we can redirect back after login
            let path = conn.request.path ?? "/"
            return conn
                .putSessionValue(returnToKey, path)
                .redirect(to: redirectTo)
        }
        return conn
    }
}

// MARK: - optionalAuth

/// Optional authentication — loads the user if present, continues as guest if not.
///
/// This is a no-op plug that serves as documentation: it signals that the
/// route supports both authenticated and anonymous access. The actual user
/// loading should happen in a preceding plug (e.g. a "fetch user" plug that
/// calls ``Nexus/Connection/setCurrentUser(_:)``).
///
/// ```swift
/// scope("/", plugs: [optionalAuth()]) {
///     GET("/") { conn in
///         if let user = conn.currentUser(User.self) {
///             // Show personalized content
///         } else {
///             // Show public content
///         }
///     }
/// }
/// ```
public func optionalAuth() -> Plug {
    { conn in conn }
}

// MARK: - requireApiAuth

/// Require bearer token authentication — returns 401 for unauthenticated API requests.
///
/// Checks that a bearer-authenticated user exists in assigns. If not,
/// returns a `401 Unauthorized` response with a `WWW-Authenticate` header
/// per RFC 6750.
///
/// The actual token validation and user loading should happen in a
/// preceding plug. This plug only checks the result.
///
/// ```swift
/// // API pipeline: bearerAuth → requireApiAuth → router
/// scope("/api/v1", plugs: [bearerAuthPlug(), requireApiAuth()]) {
///     GET("/api/v1/me") { conn in
///         let user = conn.currentUser(User.self)!
///         return conn.json(["id": user.authID])
///     }
/// }
/// ```
///
/// - Parameter realm: The authentication realm for the `WWW-Authenticate` header.
/// - Returns: A plug that enforces API authentication.
public func requireApiAuth(
    realm: String = "API"
) -> Plug {
    { conn in
        guard conn.isAuthenticated else {
            // Check if they even provided a token
            if conn.bearerToken != nil {
                // Token was provided but invalid/expired
                return conn.unauthorized(realm: realm, error: "invalid_token")
            }
            // No token at all
            return conn.unauthorized(realm: realm)
        }
        return conn
    }
}

// MARK: - fetchSessionUser

/// A plug builder that loads the authenticated user from the session.
///
/// Supply a closure that, given a user-ID string from the session, loads
/// your user model from the database (or cache). If loading succeeds, the
/// user is stored in assigns via ``Nexus/Connection/setCurrentUser(_:)``.
///
/// ```swift
/// func fetchUser() -> Plug {
///     fetchSessionUser { userID, conn in
///         guard let uuid = UUID(uuidString: userID) else { return nil }
///         return try await conn.spectro.repository()
///             .query(User.self)
///             .filter(\.id == uuid)
///             .first()
///     }
/// }
/// ```
///
/// - Parameter loader: An async closure that receives the user-ID string
///   and the current connection, returning the user or `nil`.
/// - Returns: A plug that loads the session user into assigns.
public func fetchSessionUser<U: Authenticatable>(
    _ loader: @escaping @Sendable (String, Connection) async throws -> U?
) -> Plug {
    { conn in
        guard let userID = conn.authUserID else {
            return conn // No session — continue as guest
        }

        guard let user = try await loader(userID, conn) else {
            // Session exists but user couldn't be loaded (deleted account, etc.)
            // Clear stale session data
            return conn.logoutUser()
        }

        return conn.setCurrentUser(user)
    }
}

// MARK: - fetchBearerUser

/// A plug builder that authenticates via Bearer token.
///
/// Supply a closure that, given the raw bearer token string, loads
/// the user from the database. Typically you'll hash the token with
/// ``Auth/sha256Hex(_:)`` and look up the matching row in `user_tokens`.
///
/// ```swift
/// func apiBearerAuth() -> Plug {
///     fetchBearerUser { token, conn in
///         let hashed = Auth.sha256Hex(token)
///         guard let tokenRow = try await conn.spectro.repository()
///             .query(UserToken.self)
///             .filter(\.token == hashed)
///             .filter(\.context == "api")
///             .first()
///         else { return nil }
///
///         // Check expiry
///         if let exp = tokenRow.expiresAt, exp < Date() { return nil }
///
///         return try await conn.spectro.repository()
///             .query(User.self)
///             .filter(\.id == tokenRow.userId)
///             .first()
///     }
/// }
/// ```
///
/// - Parameter loader: An async closure that receives the raw bearer token
///   and the current connection, returning the user or `nil`.
/// - Returns: A plug that loads the bearer user into assigns.
public func fetchBearerUser<U: Authenticatable>(
    _ loader: @escaping @Sendable (String, Connection) async throws -> U?
) -> Plug {
    { conn in
        guard let token = conn.bearerToken else {
            return conn
        }

        guard let user = try await loader(token, conn) else {
            return conn // Invalid token — don't halt, let requireApiAuth handle it
        }

        return conn.setBearerUser(user)
    }
}
