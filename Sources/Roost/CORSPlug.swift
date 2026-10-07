import Foundation
import HTTPTypes
import Nexus

// MARK: - CORSOrigin

/// Determines which origins are permitted for cross-origin requests.
public enum CORSOrigin: Sendable {
    /// Reflect the request's Origin header back (any origin allowed).
    case originBased

    /// Allow only a specific origin.
    case exact(String)

    /// Allow multiple specific origins.
    case allowList(Set<String>)

    /// Custom validation function. Return true to permit the origin.
    case custom(@Sendable (String) -> Bool)

    /// Wildcard `*` — incompatible with credentials.
    case any
}

// MARK: - CORS Plug

/// A plug that enables cross-origin resource sharing (CORS).
///
/// Handles both preflight (`OPTIONS`) requests and actual requests with
/// CORS headers. Preflight requests are responded to with 204 No Content
/// and the appropriate CORS headers, then halted.
///
/// ```swift
/// var plugs: [Plug] {
///     [cors(allowOrigin: .exact("https://myapp.com")), roost_requestLogger()]
/// }
/// ```
///
/// - Parameters:
///   - allowOrigin: How to validate the Origin header. Defaults to `.originBased` (any origin).
///   - allowMethods: HTTP methods to allow in preflight responses.
///   - allowHeaders: HTTP headers to allow in preflight responses.
///   - exposeHeaders: Response headers client-side JavaScript can access.
///   - maxAge: How long (seconds) the browser should cache preflight results.
///   - allowCredentials: Whether to permit cookies/credentials in cross-origin requests.
/// - Returns: A plug that manages CORS headers.
public func cors(
    allowOrigin: CORSOrigin = .originBased,
    allowMethods: [HTTPRequest.Method] = [.get, .post, .put, .patch, .delete],
    allowHeaders: [HTTPField.Name] = [.contentType, .authorization, .accept],
    exposeHeaders: [HTTPField.Name] = [],
    maxAge: Int = 86400,
    allowCredentials: Bool = false
) -> Plug {
    let allowMethodsStr = allowMethods.map { $0.rawValue }.joined(separator: ", ")
    let allowHeadersStr = allowHeaders.map { $0.rawName }.joined(separator: ", ")
    let exposeHeadersStr = exposeHeaders.map { $0.rawName }.joined(separator: ", ")
    let maxAgeStr = String(maxAge)

    // Prod warning for permissive origins
    if Roost.env == .prod {
        switch allowOrigin {
        case .originBased:
            print(
                "[CORS] Warning: .originBased allows any origin in production. Use .exact or .allowList for tighter security."
            )
        case .any:
            print("[CORS] Warning: .any (wildcard *) is incompatible with allowCredentials in production.")
        default:
            break
        }
    }

    return { conn in
        guard let origin = conn.request.headerFields[.origin] else {
            return conn
        }

        // Validate origin
        guard matchesOrigin(origin, policy: allowOrigin) else {
            return originRejected(conn)
        }

        // If preflight, respond and halt
        if conn.request.method == .options {
            var result = conn
            result.response.status = .noContent
            origin.setCORSOrigin(in: &result, allowOrigin: allowOrigin)
            result.response.headerFields[.allow] = allowMethodsStr
            result.response.headerFields[.allowHeadersName] = allowHeadersStr
            result.response.headerFields[.maxAgeName] = maxAgeStr
            if allowCredentials {
                result.response.headerFields[.credentialsName] = "true"
            }
            result.responseBody = .empty
            result.isHalted = true
            return result
        }

        // Actual request — set CORS headers and continue
        var result = conn
        origin.setCORSOrigin(in: &result, allowOrigin: allowOrigin)
        if !exposeHeaders.isEmpty {
            result.response.headerFields[.exposeHeadersName] = exposeHeadersStr
        }
        if allowCredentials {
            result.response.headerFields[.credentialsName] = "true"
        }
        return result
    }
}

// MARK: - Origin validation

private func matchesOrigin(_ origin: String, policy: CORSOrigin) -> Bool {
    switch policy {
    case .originBased:
        return true
    case .exact(let allowed):
        return origin == allowed
    case .allowList(let allowed):
        return allowed.contains(origin)
    case .custom(let validator):
        return validator(origin)
    case .any:
        return true
    }
}

// MARK: - Rejection

/// Returns a 403 Forbidden with CORS headers.
private func originRejected(_ conn: Connection) -> Connection {
    var result = conn
    result.response.status = .forbidden
    result.responseBody = .string("Forbidden: Origin not allowed")
    result.isHalted = true
    return result
}

extension String {
    fileprivate func setCORSOrigin(in conn: inout Connection, allowOrigin: CORSOrigin) {
        let value: String
        switch allowOrigin {
        case .any:
            value = "*"
        case .originBased:
            value = self
        case .exact(let allowed):
            value = allowed
        case .allowList:
            value = self
        case .custom:
            value = self
        }
        conn.response.headerFields[.accessControlAllowOrigin] = value
    }
}

// MARK: - Non-standard header names

extension HTTPField.Name {
    static let allowHeadersName = Self("Access-Control-Allow-Headers")!
    static let maxAgeName = Self("Access-Control-Max-Age")!
    static let credentialsName = Self("Access-Control-Allow-Credentials")!
    static let exposeHeadersName = Self("Access-Control-Expose-Headers")!
}
