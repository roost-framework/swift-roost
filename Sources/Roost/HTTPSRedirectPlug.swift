import Foundation
import HTTPTypes
import Nexus

// MARK: - HTTPS Redirect Plug

/// A plug that redirects HTTP requests to HTTPS.
///
/// Returns a 308 Permanent Redirect to the HTTPS equivalent of the
/// original URL. Skips requests that already arrived via HTTPS.
///
/// HTTPS detection checks (in order):
/// 1. `X-Forwarded-Proto` header equals `"https"`
/// 2. `X-Forwarded-Ssl` header equals `"on"`
///
/// If neither header is present, the request is assumed to be plaintext
/// HTTP and will be redirected.
///
/// ```swift
/// var plugs: [Plug] {
///     [httpsRedirect(), requestLogger()]
/// }
/// ```
///
/// The plug constructs the redirect URL by swapping the scheme to
/// `https://` while preserving the original host, path, and query string.
/// If the `Host` header is unavailable, falls back to `localhost`.
public func httpsRedirect() -> Plug {
    { conn in
        guard !isSecure(conn) else {
            return conn
        }

        let hostHeader = HTTPField.Name("Host")!
        let host = conn.request.headerFields[hostHeader] ?? "localhost"
        let pathAndQuery = conn.request.path ?? "/"
        let httpsURL = "https://\(host)\(pathAndQuery)"

        var result = conn
        result.isHalted = true
        result.response.status = .permanentRedirect
        result.response.headerFields[.location] = httpsURL
        return result
    }
}

// MARK: - HTTPS Detection

private func isSecure(_ conn: Connection) -> Bool {
    if let proto = conn.request.headerFields[.xForwardedProto] {
        return proto.lowercased() == "https"
    }
    if let ssl = conn.request.headerFields[.xForwardedSsl] {
        return ssl.lowercased() == "on"
    }
    return false
}

// MARK: - Forwarded headers

extension HTTPField.Name {
    static let xForwardedProto = Self("X-Forwarded-Proto")!
    static let xForwardedSsl = Self("X-Forwarded-SSL")!
}
