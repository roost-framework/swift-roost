import Foundation

/// Errors raised by the authentication subsystem.
public enum AuthError: Error, Sendable, Equatable {
    /// The supplied password is shorter than the required minimum.
    case passwordTooShort(minLength: Int)

    /// Bcrypt / PBKDF2 hashing failed internally.
    case hashingFailed(String)

    /// A stored hash string could not be parsed.
    case invalidHashFormat

    /// The user could not be found or credentials were invalid.
    /// Intentionally vague to avoid leaking which field was wrong.
    case invalidCredentials

    /// A bearer token was missing or malformed.
    case invalidToken

    /// A bearer token has expired.
    case tokenExpired

    /// The requested resource requires authentication.
    case authenticationRequired
}
