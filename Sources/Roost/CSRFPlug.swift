import Foundation
import HTTPTypes
import Nexus

/// Roost's CSRF protection plug wrapping Nexus's `csrfProtection(_:)`.
///
/// Adds Roost-specific features on top of Nexus's core CSRF validation:
///
/// - **Explicit API opt-out** — `skipJSON: true` bypasses checks for JSON requests.
///   Only enable it for an API authenticated without cookies. The default protects JSON too.
/// - **Path exclusions** — The `except` parameter lists paths that skip validation
///   entirely (e.g., webhook endpoints).
/// - **Form rendering** — `conn.render(...)` supplies the token to Roost's
///   `<.form>` component automatically, without page-level token properties.
/// - **Low-level assigns** — Injects `csrfToken` (the raw token string) and
///   `csrfTag` (a ready-to-use `<input type="hidden">` element) into
///   `Connection.assigns` for use in templates.
///
/// Requires `session(store:)` earlier in the pipeline, normally installed by
/// configuring `RoostApp.sessionStore`.
///
/// ```swift
/// let sessionStore: (any SessionStore)? = MemorySessionStore()
/// var plugs: [Plug] {
///     [
///         bodyParser(),
///         methodOverride(),
///         roost_csrfProtection(except: ["/webhooks/stripe"]),
///         // ...
///     ]
/// }
/// ```
///
/// In a typed ESW template rendered through `conn.render(...)`:
/// ```html
/// <.form action="/submit" method="post">
///   <input type="text" name="title">
///   <button>Submit</button>
/// </.form>
/// ```
///
/// - Parameters:
///   - except: Paths to skip CSRF validation for (exact match).
///   - skipJSON: Opt out of JSON checks for APIs authenticated without cookies.
///     Defaults to `false`.
/// - Returns: A plug that enforces CSRF protection with Roost conventions.
public func roost_csrfProtection(
    except: [String] = [],
    skipJSON: Bool = false
) -> Plug {
    let config = CSRFConfig()
    let nexusCSRF = csrfProtection(config)
    let exceptSet = Set(except)

    return { conn in
        let path = conn.request.path ?? "/"

        // Skip excluded paths
        if exceptSet.contains(path) {
            return injectCSRFAssigns(conn: conn, config: config)
        }

        // Skip JSON API requests — they use bearer tokens, not cookies
        if skipJSON, let contentType = conn.getReqHeader(.contentType),
           contentType.contains("application/json") {
            return conn
        }

        // Run Nexus CSRF validation
        let result = try await nexusCSRF(conn)

        // If halted (e.g. 403 Forbidden), return as-is
        guard !result.isHalted else {
            return result
        }

        // Inject csrfToken and csrfTag into assigns for templates
        return injectCSRFAssigns(conn: result, config: config)
    }
}

/// Generates or retrieves the CSRF token and injects it (along with an
/// HTML hidden input tag) into the connection's assigns.
private func injectCSRFAssigns(
    conn: Connection,
    config: CSRFConfig
) -> Connection {
    let (token, updated) = csrfToken(conn: conn, config: config)
    let tag = """
        <input type="hidden" name="\(config.formParam)" value="\(token)">
        """
    return updated
        .assign(key: "csrfToken", value: token)
        .assign(key: "csrfTag", value: tag)
}
