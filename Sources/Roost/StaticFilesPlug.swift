import Foundation
import HTTPTypes
import Nexus

/// MIME type mapping for common web file types.
private let mimeTypes: [String: String] = [
    "html": "text/html; charset=utf-8",
    "htm": "text/html; charset=utf-8",
    "css": "text/css; charset=utf-8",
    "js": "application/javascript; charset=utf-8",
    "mjs": "application/javascript; charset=utf-8",
    "json": "application/json",
    "xml": "application/xml",
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "gif": "image/gif",
    "webp": "image/webp",
    "svg": "image/svg+xml",
    "ico": "image/x-icon",
    "woff2": "font/woff2",
    "woff": "font/woff",
    "ttf": "font/ttf",
    "otf": "font/otf",
    "eot": "application/vnd.ms-fontobject",
    "pdf": "application/pdf",
    "zip": "application/zip",
    "gz": "application/gzip",
    "mp4": "video/mp4",
    "webm": "video/webm",
    "mp3": "audio/mpeg",
    "ogg": "audio/ogg",
    "wav": "audio/wav",
    "txt": "text/plain; charset=utf-8",
    "map": "application/json",
    "wasm": "application/wasm",
]

/// Roost's static file serving plug.
///
/// Serves files from a directory (default: `Public/`) at a URL prefix
/// (default: `/`). Adds Roost-specific features on top of Nexus's
/// lower-level `staticFiles(_:)` plug:
///
/// - **Hidden file protection** — files or directories starting with `.`
///   are never served (returns 404).
/// - **Environment-aware cache headers** — `no-cache` in dev mode;
///   fingerprinted assets get `immutable` / 1-year max-age in prod.
/// - **Directory request rejection** — requests that resolve to a
///   directory pass through to the next plug (typically the router).
/// - **Rich MIME type detection** — covers fonts, media, WebAssembly,
///   source maps, and more.
///
/// ```swift
/// // In your RoostApp:
/// var plugs: [Plug] {
///     [roost_staticFiles(), requestId(), requestLogger()]
/// }
/// ```
///
/// - Parameters:
///   - directory: Filesystem directory to serve from. Defaults to `"Public"`.
///   - prefix: URL prefix to match. Defaults to `"/"`.
/// - Returns: A `Plug` that serves static files with Roost conventions.
public func roost_staticFiles(
    from directory: String = "Public",
    at prefix: String = "/"
) -> Plug {
    // Resolve the base directory once at plug-creation time so that
    // later working-directory changes don't affect file resolution.
    let baseDir = URL(fileURLWithPath: directory).standardized
    let basePath = baseDir.path
    let normalizedPrefix = prefix.hasSuffix("/") && prefix.count > 1
        ? String(prefix.dropLast())
        : prefix

    return { conn in
        // Only serve GET and HEAD requests
        guard conn.request.method == .get || conn.request.method == .head else {
            return conn
        }

        let requestPath = conn.request.path ?? "/"

        // Must match the URL prefix
        guard requestPath == normalizedPrefix
            || requestPath.hasPrefix(normalizedPrefix == "/" ? "/" : normalizedPrefix + "/")
        else {
            return conn
        }

        // Extract the relative path after the prefix
        let relativePath: String
        if normalizedPrefix == "/" {
            relativePath = String(requestPath.dropFirst())  // drop leading /
        } else if requestPath == normalizedPrefix {
            // Requesting the prefix itself with no file — pass through
            return conn
        } else {
            relativePath = String(requestPath.dropFirst(normalizedPrefix.count + 1))
        }

        // Empty relative path means root was requested — pass through
        guard !relativePath.isEmpty else { return conn }

        // Validate path segments
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        for segment in segments {
            // Path traversal protection
            if segment == ".." {
                var copy = conn
                copy.response.status = .badRequest
                copy.responseBody = .string("Bad Request")
                copy.isHalted = true
                return copy
            }
            // Hidden file / directory protection
            if segment.hasPrefix(".") {
                var copy = conn
                copy.response.status = .notFound
                copy.responseBody = .string("Not Found")
                copy.isHalted = true
                return copy
            }
        }

        // Null byte protection (raw \0 and URL-encoded %00)
        if relativePath.contains("\0") || relativePath.lowercased().contains("%00") {
            var copy = conn
            copy.response.status = .badRequest
            copy.responseBody = .string("Bad Request")
            copy.isHalted = true
            return copy
        }

        // Resolve full filesystem path
        let fileURL = baseDir.appendingPathComponent(relativePath).standardized
        let filePath = fileURL.path

        // Defense in depth: resolved path must still be under the base directory
        guard filePath.hasPrefix(basePath) else {
            var copy = conn
            copy.response.status = .forbidden
            copy.responseBody = .string("Forbidden")
            copy.isHalted = true
            return copy
        }

        // Check existence — pass through if missing or if it is a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            return conn  // Not found or directory — let the router handle it
        }

        // Serve the file via Nexus's sendFile (sets status, streams body, halts)
        let ext = (relativePath as NSString).pathExtension.lowercased()
        let contentType = mimeTypes[ext] ?? "application/octet-stream"

        var result = try conn.sendFile(path: filePath, contentType: contentType)

        // Environment-aware cache headers
        let cacheControl: String
        switch Roost.env {
        case .dev:
            cacheControl = "no-cache"
        case .test, .prod:
            // Fingerprinted assets (e.g. app-3a7f2b1c.js) get aggressive caching
            let filename = (relativePath as NSString).lastPathComponent
            if filename.range(of: #"[.\-][a-f0-9]{8,}"#, options: .regularExpression) != nil {
                cacheControl = "public, max-age=31536000, immutable"
            } else {
                cacheControl = "public, max-age=3600"
            }
        }
        result = result.putRespHeader(.cacheControl, cacheControl)

        // HEAD requests: keep headers but clear the body
        if conn.request.method == .head {
            result.responseBody = .empty
        }

        return result
    }
}
