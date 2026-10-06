import Foundation
import HTTPTypes
import Nexus

// MARK: - Compression re-export

/// Nexus's built-in `Compression` is already available via `import Roost`.
/// This alias provides a function-style API matching the other plugs.
///
/// A plug that compresses text responses with gzip or deflate.
///
/// ```swift
/// var plugs: [Plug] {
///     [compress(), router()]
/// }
/// ```
///
/// - Parameters:
///   - minBytes: Minimum response body size before compression is applied.
///     Default is 1024 bytes.
/// - Returns: A `Compression` instance that compresses eligible responses.
public func compress(minBytes: Int = 1024) -> Compression {
    Compression(minimumLength: minBytes)
}

// MARK: - Compressible MIME types

/// Default set of MIME types that benefit from compression.
public let defaultCompressibleTypes: Set<String> = [
    // Text
    "text/html",
    "text/plain",
    "text/css",
    "text/xml",
    "text/csv",
    "text/calendar",
    // JavaScript
    "application/javascript",
    "application/json",
    "application/xml",
    "application/x-javascript",
    // SVG (text-based image format)
    "image/svg+xml",
    "application/ld+json",
    // Web manifests
    "application/manifest+json",
]
