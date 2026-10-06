import Crypto
import Foundation

/// URL-safe token signing and verification using HMAC-SHA256.
///
/// Tokens encode a JSON payload containing the signed data and an
/// issued-at timestamp. The format is `base64url(payload).base64url(signature)`.
///
/// ```swift
/// let token = RoostToken.sign("user:42", secret: "s3cret")
/// let data  = RoostToken.verify(token, secret: "s3cret")
/// // data == "user:42"
/// ```
public enum RoostToken {

    // MARK: - Public API

    /// Signs `data` and returns a URL-safe token string.
    ///
    /// - Parameters:
    ///   - data: The plaintext value to embed in the token.
    ///   - secret: The HMAC secret key.
    ///   - maxAge: Optional lifetime in seconds. Included for documentation
    ///     purposes only — expiry is enforced at verification time.
    /// - Returns: A token in the format `base64url(payload).base64url(signature)`.
    public static func sign(_ data: String, secret: String, maxAge: Int? = nil) -> String {
        let iat = Int(Date().timeIntervalSince1970)
        let payload = buildPayload(data: data, iat: iat)
        let signature = hmac(payload, secret: secret)
        return "\(base64URLEncode(payload)).\(base64URLEncode(signature))"
    }

    /// Verifies a token and returns the original data if valid.
    ///
    /// - Parameters:
    ///   - token: The token string produced by ``sign(_:secret:maxAge:)``.
    ///   - secret: The HMAC secret key (must match the signing key).
    ///   - maxAge: Optional lifetime in seconds. If provided, tokens whose
    ///     `iat` is older than `now - maxAge` are rejected.
    /// - Returns: The original data string, or `nil` if the token is
    ///   invalid, tampered with, or expired.
    public static func verify(_ token: String, secret: String, maxAge: Int? = nil) -> String? {
        let parts = token.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        guard let payloadBytes = base64URLDecode(String(parts[0])),
              let signatureBytes = base64URLDecode(String(parts[1]))
        else { return nil }

        // Verify HMAC
        let expectedSignature = hmac(payloadBytes, secret: secret)
        guard constantTimeEqual(signatureBytes, expectedSignature) else { return nil }

        // Parse payload JSON
        guard let json = try? JSONSerialization.jsonObject(with: Data(payloadBytes)) as? [String: Any],
              let data = json["data"] as? String,
              let iat = json["iat"] as? Int
        else { return nil }

        // Check expiry
        if let maxAge {
            let now = Int(Date().timeIntervalSince1970)
            if iat + maxAge < now {
                return nil
            }
        }

        return data
    }

    // MARK: - Internal Helpers

    private static func buildPayload(data: String, iat: Int) -> [UInt8] {
        let json = "{\"data\":\"\(escapeJSON(data))\",\"iat\":\(iat)}"
        return Array(json.utf8)
    }

    private static func hmac(_ message: [UInt8], secret: String) -> [UInt8] {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message), using: key)
        return Array(mac)
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[i] ^ b[i]
        }
        return result == 0
    }

    // MARK: - Base64URL

    private static func base64URLEncode(_ bytes: [UInt8]) -> String {
        Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> [UInt8]? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to a multiple of 4
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return Array(data)
    }

    // MARK: - JSON Escaping

    private static func escapeJSON(_ string: String) -> String {
        var result = ""
        for char in string {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(char)
            }
        }
        return result
    }
}
