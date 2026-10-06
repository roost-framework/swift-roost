import Crypto
import Foundation
import Testing

@testable import Roost

@Suite("RoostToken Signing & Verification")
struct RoostTokenTests {

    let secret = "test-secret-key-for-hmac"

    // MARK: - Token Format

    @Test("sign produces a URL-safe string with no +, /, or = characters")
    func signProducesURLSafeString() {
        let token = RoostToken.sign("hello", secret: secret)
        #expect(!token.contains("+"))
        #expect(!token.contains("/"))
        #expect(!token.contains("="))
    }

    @Test("token format has exactly one dot separator")
    func tokenHasOneDot() {
        let token = RoostToken.sign("payload", secret: secret)
        let dotCount = token.filter { $0 == "." }.count
        #expect(dotCount == 1)
    }

    // MARK: - Roundtrip

    @Test("verify returns original data for a valid token")
    func verifyReturnsOriginalData() {
        let data = "user:42"
        let token = RoostToken.sign(data, secret: secret)
        let result = RoostToken.verify(token, secret: secret)
        #expect(result == data)
    }

    @Test("sign/verify roundtrip with special characters in data")
    func roundtripWithSpecialCharacters() {
        let data = "email=foo@bar.com&name=\"John Doe\"&path=/a/b?c=1"
        let token = RoostToken.sign(data, secret: secret)
        let result = RoostToken.verify(token, secret: secret)
        #expect(result == data)
    }

    // MARK: - Tampering

    @Test("verify returns nil for tampered signature")
    func tamperedSignature() {
        let token = RoostToken.sign("data", secret: secret)
        let parts = token.split(separator: ".")
        let tampered = "\(parts[0]).AAAA\(parts[1])"
        #expect(RoostToken.verify(tampered, secret: secret) == nil)
    }

    @Test("verify returns nil for tampered payload")
    func tamperedPayload() {
        let token = RoostToken.sign("data", secret: secret)
        let parts = token.split(separator: ".")
        let tampered = "AAAA\(parts[0]).\(parts[1])"
        #expect(RoostToken.verify(tampered, secret: secret) == nil)
    }

    @Test("verify returns nil for wrong secret")
    func wrongSecret() {
        let token = RoostToken.sign("data", secret: secret)
        #expect(RoostToken.verify(token, secret: "wrong-secret") == nil)
    }

    // MARK: - Expiry

    @Test("verify with maxAge rejects expired tokens")
    func expiredToken() {
        // Build a token with an old iat by signing and then manually
        // constructing a payload with a past timestamp.
        let oldIat = Int(Date().timeIntervalSince1970) - 3600 // 1 hour ago
        let payload = "{\"data\":\"old\",\"iat\":\(oldIat)}"
        let payloadBytes = Array(payload.utf8)

        // Re-create the token manually using the same format
        let token = buildToken(payloadBytes: payloadBytes, secret: secret)

        // maxAge of 60 seconds should reject a 1-hour-old token
        #expect(RoostToken.verify(token, secret: secret, maxAge: 60) == nil)
    }

    @Test("verify with maxAge accepts tokens within the window")
    func tokenWithinWindow() {
        let token = RoostToken.sign("fresh", secret: secret)
        // maxAge of 3600 seconds — token was just created
        let result = RoostToken.verify(token, secret: secret, maxAge: 3600)
        #expect(result == "fresh")
    }

    @Test("verify without maxAge accepts old tokens (no expiry)")
    func noExpiryAcceptsOldTokens() {
        let oldIat = Int(Date().timeIntervalSince1970) - 86400 * 365 // 1 year ago
        let payload = "{\"data\":\"ancient\",\"iat\":\(oldIat)}"
        let payloadBytes = Array(payload.utf8)
        let token = buildToken(payloadBytes: payloadBytes, secret: secret)

        let result = RoostToken.verify(token, secret: secret)
        #expect(result == "ancient")
    }

    // MARK: - Helpers

    /// Builds a token from raw payload bytes and a secret, mirroring
    /// the internal format used by ``RoostToken``.
    private func buildToken(payloadBytes: [UInt8], secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payloadBytes), using: key)
        let sigBytes = Array(mac)

        func base64URLEncode(_ bytes: [UInt8]) -> String {
            Data(bytes)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        return "\(base64URLEncode(payloadBytes)).\(base64URLEncode(sigBytes))"
    }
}
