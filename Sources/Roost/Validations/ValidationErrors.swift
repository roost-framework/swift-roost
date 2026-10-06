import Foundation

// MARK: - Validation Errors

/// Collects field-level and model-level validation errors.
///
/// ```swift
/// var errors = ValidationErrors()
/// errors.add(field: "email", "can't be blank")
/// errors.add(field: "email", "is not a valid email")
/// errors.add("record is stale")
///
/// errors.isValid       // false
/// errors["email"]      // ["can't be blank", "is not a valid email"]
/// errors.modelErrors   // ["record is stale"]
/// ```
public struct ValidationErrors: Error, Sendable, Equatable, Codable {
    /// Per-field error messages keyed by field name.
    public private(set) var fieldErrors: [String: [String]] = [:]

    /// Model-level error messages (not tied to a specific field).
    public private(set) var modelErrors: [String] = []

    public init() {}

    /// `true` when there are no errors at all.
    public var isValid: Bool { fieldErrors.isEmpty && modelErrors.isEmpty }

    /// Add a field-level error.
    public mutating func add(field: String, _ message: String) {
        fieldErrors[field, default: []].append(message)
    }

    /// Add a model-level error.
    public mutating func add(_ message: String) {
        modelErrors.append(message)
    }

    /// Get all errors for a specific field. Returns `[]` if none.
    public subscript(field: String) -> [String] {
        fieldErrors[field] ?? []
    }

    /// Total number of individual error messages.
    public var count: Int {
        fieldErrors.values.reduce(0) { $0 + $1.count } + modelErrors.count
    }

    /// Merge another `ValidationErrors` into this one.
    public mutating func merge(_ other: ValidationErrors) {
        for (field, messages) in other.fieldErrors {
            for msg in messages {
                add(field: field, msg)
            }
        }
        for msg in other.modelErrors {
            add(msg)
        }
    }

    /// Encode as JSON `Data`, suitable for API error responses.
    ///
    /// ```swift
    /// // Returns: {"fieldErrors":{"email":["can't be blank"]},"modelErrors":[]}
    /// let body = try changeset.errors.jsonData()
    /// return conn.json(body, status: .unprocessableEntity)
    /// ```
    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
