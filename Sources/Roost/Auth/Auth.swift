import Crypto
import Foundation

/// Core authentication utilities: password hashing, verification, and token generation.
///
/// Password hashing uses PBKDF2-HMAC-SHA256 with 600,000 iterations and a
/// random 32-byte salt. Tokens are cryptographically random, URL-safe base64.
///
/// ```swift
/// let hash = try Auth.hashPassword("s3cret-pass!")
/// let ok   = Auth.verifyPassword("s3cret-pass!", against: hash)
/// let tok  = Auth.generateToken()
/// ```
public enum Auth {

    // MARK: - Configuration

    /// Minimum accepted password length.
    public static let minimumPasswordLength = 8

    /// PBKDF2 iteration count (OWASP 2023 recommendation for SHA-256).
    static let pbkdf2Iterations = 600_000

    /// Derived key length in bytes.
    static let derivedKeyLength = 32

    /// Salt length in bytes.
    static let saltLength = 32

    // MARK: - Password Hashing

    /// Hash a password using PBKDF2-HMAC-SHA256.
    ///
    /// - Parameter password: Plain text password (must be >= ``minimumPasswordLength`` chars).
    /// - Returns: Encoded hash string in the format `pbkdf2-sha256$iterations$base64url(salt)$base64url(hash)`.
    /// - Throws: ``AuthError/passwordTooShort(minLength:)`` when the password is too short.
    public static func hashPassword(_ password: String) throws -> String {
        guard password.count >= minimumPasswordLength else {
            throw AuthError.passwordTooShort(minLength: minimumPasswordLength)
        }

        let salt = generateRandomBytes(count: saltLength)
        let hash = pbkdf2(
            password: password,
            salt: salt,
            iterations: pbkdf2Iterations,
            keyLength: derivedKeyLength
        )

        let saltEncoded = base64URLEncode(salt)
        let hashEncoded = base64URLEncode(hash)
        return "pbkdf2-sha256$\(pbkdf2Iterations)$\(saltEncoded)$\(hashEncoded)"
    }

    /// Verify a plain-text password against a stored hash.
    ///
    /// Uses constant-time comparison to prevent timing attacks.
    ///
    /// - Parameters:
    ///   - password: Plain text password to check.
    ///   - hash: Previously stored hash from ``hashPassword(_:)``.
    /// - Returns: `true` when the password matches the hash.
    public static func verifyPassword(_ password: String, against hash: String) -> Bool {
        let parts = hash.split(separator: "$")
        guard parts.count == 4,
              parts[0] == "pbkdf2-sha256",
              let iterations = Int(parts[1]),
              let salt = base64URLDecode(String(parts[2])),
              let storedHash = base64URLDecode(String(parts[3]))
        else {
            return false
        }

        let computed = pbkdf2(
            password: password,
            salt: salt,
            iterations: iterations,
            keyLength: storedHash.count
        )

        return constantTimeEqual(computed, storedHash)
    }

    // MARK: - Token Generation

    /// Generate a cryptographically random, URL-safe base64 token.
    ///
    /// - Parameter bytes: Number of random bytes (default: 32, producing a 43-char token).
    /// - Returns: URL-safe base64-encoded token string.
    public static func generateToken(bytes: Int = 32) -> String {
        base64URLEncode(generateRandomBytes(count: bytes))
    }

    /// SHA-256 hash of a string, returned as a lowercase hex digest.
    ///
    /// Used internally to hash tokens before database storage so that
    /// a database leak doesn't expose raw bearer tokens.
    public static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - PBKDF2 (HMAC-SHA256)

    /// Pure-Swift PBKDF2 implementation using `Crypto`'s HMAC-SHA256.
    static func pbkdf2(
        password: String,
        salt: [UInt8],
        iterations: Int,
        keyLength: Int
    ) -> [UInt8] {
        let key = SymmetricKey(data: Data(password.utf8))
        var derivedKey: [UInt8] = []
        var block: UInt32 = 1

        while derivedKey.count < keyLength {
            // U1 = HMAC(password, salt || INT_32_BE(block))
            var input = salt
            withUnsafeBytes(of: block.bigEndian) { input.append(contentsOf: $0) }

            var u = Array(HMAC<SHA256>.authenticationCode(for: input, using: key))
            var result = u

            // U2 .. Uc
            for _ in 1..<iterations {
                u = Array(HMAC<SHA256>.authenticationCode(for: u, using: key))
                for i in 0..<result.count {
                    result[i] ^= u[i]
                }
            }

            derivedKey.append(contentsOf: result)
            block += 1
        }

        return Array(derivedKey.prefix(keyLength))
    }

    // MARK: - Helpers

    /// Constant-time byte-array comparison.
    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    /// Generate cryptographically random bytes using the system CSPRNG.
    static func generateRandomBytes(count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    /// URL-safe base64 encoding (no padding).
    static func base64URLEncode(_ bytes: [UInt8]) -> String {
        Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// URL-safe base64 decoding.
    static func base64URLDecode(_ string: String) -> [UInt8]? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return Array(data)
    }
}
