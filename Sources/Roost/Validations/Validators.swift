import Foundation

// MARK: - Validation Message

/// A message produced by a validator.
public enum ValidationMessage: Sendable {
    /// Error on a specific field.
    case field(String, String)
    /// Model-level error.
    case model(String)
}

// MARK: - Validator Rule

/// A validation rule that checks data and produces error messages.
///
/// Built-in rules are available as static factory methods:
///
/// ```swift
/// let rules: [ValidatorRule<MyInput>] = [
///     .required("name") { $0.name },
///     .length("name", { $0.name }, min: 2, max: 100),
///     .email("email") { $0.email },
///     .number("age", { $0.age }, greaterThanOrEqual: 18),
///     .inclusion("role", { $0.role }, in: ["admin", "user", "guest"]),
/// ]
/// ```
public struct ValidatorRule<T: Sendable>: Sendable {
    /// The validation closure. Returns empty array when valid.
    public let check: @Sendable (T) async -> [ValidationMessage]

    /// Create a custom validator rule.
    public init(_ check: @escaping @Sendable (T) async -> [ValidationMessage]) {
        self.check = check
    }
}

// MARK: - Required

extension ValidatorRule {

    /// Validates that a string field is present and not blank.
    ///
    /// Trims whitespace before checking.
    ///
    /// ```swift
    /// .required("title") { $0.title }
    /// ```
    public static func required(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> String
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            let value = accessor(data)
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                return [.field(field, "can't be blank")]
            }
            return []
        }
    }

    /// Validates that an optional string field is present, not nil, and not blank.
    ///
    /// ```swift
    /// .required("bio") { $0.bio }  // bio: String?
    /// ```
    public static func required(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> String?
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            guard let value = accessor(data) else {
                return [.field(field, "can't be blank")]
            }
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                return [.field(field, "can't be blank")]
            }
            return []
        }
    }

    /// Validates that an optional field is not nil.
    ///
    /// ```swift
    /// .requiredValue("categoryId") { $0.categoryId }  // categoryId: UUID?
    /// ```
    public static func requiredValue<V: Sendable>(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> V?
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            if accessor(data) == nil {
                return [.field(field, "can't be blank")]
            }
            return []
        }
    }
}

// MARK: - Length

extension ValidatorRule {

    /// Validates string length with min, max, or exact constraints.
    ///
    /// ```swift
    /// .length("name", { $0.name }, min: 2, max: 50)
    /// .length("code", { $0.code }, exact: 6)
    /// ```
    public static func length(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> String,
        min: Int? = nil,
        max: Int? = nil,
        exact: Int? = nil
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            let value = accessor(data)
            let len = value.count
            var messages: [ValidationMessage] = []

            if let exact = exact {
                if len != exact {
                    messages.append(.field(field, "should be \(exact) characters"))
                }
            } else {
                if let min = min, len < min {
                    messages.append(.field(field, "should be at least \(min) characters"))
                }
                if let max = max, len > max {
                    messages.append(.field(field, "should be at most \(max) characters"))
                }
            }
            return messages
        }
    }
}

// MARK: - Format

extension ValidatorRule {

    /// Validates that a string matches a regex pattern.
    ///
    /// ```swift
    /// .format("slug", { $0.slug }, pattern: "^[a-z0-9-]+$", message: "must be lowercase with dashes")
    /// ```
    public static func format(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> String,
        pattern: String,
        message: String? = nil
    ) -> ValidatorRule<T> {
        // Compile regex once at rule creation, not per-validation.
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ValidatorRule { _ in [.model("Invalid regex pattern: \(pattern)")] }
        }
        return ValidatorRule { data in
            let value = accessor(data)
            let range = NSRange(value.startIndex..., in: value)
            if regex.firstMatch(in: value, range: range) == nil {
                return [.field(field, message ?? "has invalid format")]
            }
            return []
        }
    }

    /// Validates email format (case-insensitive).
    ///
    /// ```swift
    /// .email("email") { $0.email }
    /// ```
    public static func email(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> String
    ) -> ValidatorRule<T> {
        format(
            field, accessor,
            pattern: "(?i)^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$",
            message: "is not a valid email"
        )
    }

    /// Validates URL format (http/https).
    ///
    /// ```swift
    /// .url("website") { $0.website }
    /// ```
    public static func url(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> String
    ) -> ValidatorRule<T> {
        format(
            field, accessor,
            pattern: "^https?://.+",
            message: "is not a valid URL"
        )
    }
}

// MARK: - Inclusion / Exclusion

extension ValidatorRule {

    /// Validates that a value is in an allowed set.
    ///
    /// ```swift
    /// .inclusion("role", { $0.role }, in: ["admin", "user", "guest"])
    /// ```
    public static func inclusion<V: Equatable & Sendable>(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> V,
        in allowed: [V],
        message: String? = nil
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            let value = accessor(data)
            if !allowed.contains(value) {
                return [.field(field, message ?? "is not included in the list")]
            }
            return []
        }
    }

    /// Validates that a value is not in a disallowed set.
    ///
    /// ```swift
    /// .exclusion("username", { $0.username }, from: ["admin", "root", "system"])
    /// ```
    public static func exclusion<V: Equatable & Sendable>(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> V,
        from disallowed: [V],
        message: String? = nil
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            let value = accessor(data)
            if disallowed.contains(value) {
                return [.field(field, message ?? "is reserved")]
            }
            return []
        }
    }
}

// MARK: - Confirmation

extension ValidatorRule {

    /// Validates that two fields have matching values (e.g. password confirmation).
    ///
    /// ```swift
    /// .confirmation(
    ///     "password", { $0.password },
    ///     confirmationField: "passwordConfirmation", { $0.passwordConfirmation }
    /// )
    /// ```
    public static func confirmation(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> String,
        confirmationField: String,
        _ confirmationAccessor: @escaping @Sendable (T) -> String
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            let value = accessor(data)
            let confirmation = confirmationAccessor(data)
            if value != confirmation {
                return [.field(confirmationField, "doesn't match \(field)")]
            }
            return []
        }
    }
}

// MARK: - Number

extension ValidatorRule {

    /// Validates a numeric value against range constraints.
    ///
    /// ```swift
    /// .number("age", { $0.age }, greaterThanOrEqual: 18)
    /// .number("price", { $0.price }, greaterThan: 0, lessThan: 10000)
    /// ```
    public static func number<N: Comparable & Sendable>(
        _ field: String,
        _ accessor: @escaping @Sendable (T) -> N,
        greaterThan: N? = nil,
        greaterThanOrEqual: N? = nil,
        lessThan: N? = nil,
        lessThanOrEqual: N? = nil
    ) -> ValidatorRule<T> {
        ValidatorRule { data in
            let value = accessor(data)
            var messages: [ValidationMessage] = []

            if let gt = greaterThan, !(value > gt) {
                messages.append(.field(field, "must be greater than \(gt)"))
            }
            if let gte = greaterThanOrEqual, !(value >= gte) {
                messages.append(.field(field, "must be greater than or equal to \(gte)"))
            }
            if let lt = lessThan, !(value < lt) {
                messages.append(.field(field, "must be less than \(lt)"))
            }
            if let lte = lessThanOrEqual, !(value <= lte) {
                messages.append(.field(field, "must be less than or equal to \(lte)"))
            }
            return messages
        }
    }
}

// MARK: - Custom

extension ValidatorRule {

    /// Custom synchronous validation.
    ///
    /// ```swift
    /// .custom { data in
    ///     if data.startDate > data.endDate {
    ///         return [.field("endDate", "must be after start date")]
    ///     }
    ///     return []
    /// }
    /// ```
    public static func custom(
        _ check: @escaping @Sendable (T) -> [ValidationMessage]
    ) -> ValidatorRule<T> {
        ValidatorRule { data in check(data) }
    }

    /// Custom async validation (e.g. database uniqueness checks).
    ///
    /// ```swift
    /// .customAsync { data in
    ///     let exists = await db.exists(User.self, where: "email", equals: data.email)
    ///     if exists { return [.field("email", "has already been taken")] }
    ///     return []
    /// }
    /// ```
    public static func customAsync(
        _ check: @escaping @Sendable (T) async -> [ValidationMessage]
    ) -> ValidatorRule<T> {
        ValidatorRule(check)
    }
}
