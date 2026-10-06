import Foundation

/// Server binding settings and optional transport configuration.
///
/// Roost's current bootstrap applies only `host` and `port`. The TLS and HTTP/2
/// fields are not yet connected to the running Hummingbird server.
public struct ServerConfig: Sendable {
    public let host: String
    public let port: Int

    /// Requested TLS configuration. Roost's bootstrap does not apply it yet.
    public let tls: TLSConfig?

    /// Requested HTTP/2 support. Setting `tls` also sets this value to `true`,
    /// but Roost's bootstrap does not yet enable HTTP/2 on the running server.
    public let http2: Bool

    /// TLS certificate and key pair.
    public struct TLSConfig: Sendable {
        /// Path to the PEM-encoded certificate file.
        public let certificatePath: String
        /// Path to the PEM-encoded private key file.
        public let keyPath: String

        public init(certificatePath: String, keyPath: String) {
            self.certificatePath = certificatePath
            self.keyPath = keyPath
        }
    }

    // MARK: - Init

    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        tls: TLSConfig? = nil,
        http2: Bool = false
    ) {
        self.host = host
        self.port = port
        self.tls = tls
        // If TLS is configured, HTTP/2 is automatically enabled.
        self.http2 = tls != nil ? true : http2
    }

    /// Reads `ROOST_HOST` and `ROOST_PORT` from the environment,
    /// falling back to the provided defaults.
    public static func fromEnvironment(
        defaultHost: String = "127.0.0.1",
        defaultPort: Int = 8080
    ) -> ServerConfig {
        let host = ProcessInfo.processInfo.environment["ROOST_HOST"] ?? defaultHost
        let port = ProcessInfo.processInfo.environment["ROOST_PORT"]
            .flatMap(Int.init) ?? defaultPort
        return ServerConfig(host: host, port: port)
    }

    // MARK: - Validation

    /// Validates that any configured TLS certificate and key files exist on
    /// disk. Returns a descriptive error string on failure, or nil if valid.
    public func validate() -> [String]? {
        var errors: [String] = []

        if let tls {
            if !FileManager.default.fileExists(atPath: tls.certificatePath) {
                errors.append("TLS certificate file not found: \(tls.certificatePath)")
            }
            if !FileManager.default.fileExists(atPath: tls.keyPath) {
                errors.append("TLS key file not found: \(tls.keyPath)")
            }
        }

        return errors.isEmpty ? nil : errors
    }
}
