import Foundation

// MARK: - Changeset Action

/// The action a changeset represents.
public enum ChangesetAction: String, Sendable {
    case create
    case update
    case delete
}

// MARK: - Validation Strategy

/// Controls how validators are executed.
public enum ValidationStrategy: Sendable {
    /// Run validators sequentially in order (default).
    /// Better for clear, deterministic error ordering.
    case sequential

    /// Run all validators concurrently via a task group.
    /// Faster when validators perform I/O (e.g. uniqueness checks),
    /// but error ordering is non-deterministic.
    case concurrent
}

// MARK: - Changeset

/// A changeset wraps data being validated before persistence.
///
/// Inspired by Phoenix/Ecto changesets but adapted for Swift's type system.
/// Instead of untyped `[String: Any]` dicts, validators use typed accessors.
///
/// ```swift
/// struct CreatePostInput: Sendable {
///     let title: String
///     let body: String
/// }
///
/// var changeset = Changeset(data: input, action: .create)
/// await changeset.validate(using: [
///     .required("title") { $0.title },
///     .length("body", { $0.body }, min: 10),
/// ])
///
/// if changeset.isValid {
///     let data = try changeset.requireValid()
///     // save to database...
/// }
/// ```
public struct Changeset<T: Sendable>: Sendable {
    /// The data being validated.
    public let data: T

    /// The original record, if updating an existing one.
    public let original: T?

    /// Whether this changeset is for create, update, or delete.
    public let action: ChangesetAction

    /// Collected validation errors.
    public private(set) var errors: ValidationErrors

    /// Create a new changeset.
    ///
    /// - Parameters:
    ///   - data: The data to validate.
    ///   - original: The original record (for updates).
    ///   - action: The changeset action (default: `.create`).
    public init(data: T, original: T? = nil, action: ChangesetAction = .create) {
        self.data = data
        self.original = original
        self.action = action
        self.errors = ValidationErrors()
    }

    /// `true` when there are no validation errors.
    public var isValid: Bool { errors.isValid }

    /// Run all validation rules, replacing any existing errors.
    ///
    /// ```swift
    /// // Sequential (default) — deterministic error order
    /// await changeset.validate(using: [
    ///     .required("email") { $0.email },
    ///     .email("email") { $0.email },
    /// ])
    ///
    /// // Concurrent — faster for I/O-heavy validators
    /// await changeset.validate(using: rules, strategy: .concurrent)
    /// ```
    ///
    /// - Parameters:
    ///   - rules: Validation rules to apply.
    ///   - strategy: Execution strategy (default: `.sequential`).
    public mutating func validate(
        using rules: [ValidatorRule<T>],
        strategy: ValidationStrategy = .sequential
    ) async {
        errors = ValidationErrors()

        switch strategy {
        case .sequential:
            for rule in rules {
                let messages = await rule.check(data)
                for msg in messages {
                    applyMessage(msg)
                }
            }

        case .concurrent:
            let data = self.data
            let allMessages = await withTaskGroup(
                of: [ValidationMessage].self,
                returning: [[ValidationMessage]].self
            ) { group in
                for rule in rules {
                    group.addTask { await rule.check(data) }
                }
                var results: [[ValidationMessage]] = []
                for await messages in group {
                    results.append(messages)
                }
                return results
            }
            for messages in allMessages {
                for msg in messages {
                    applyMessage(msg)
                }
            }
        }
    }

    /// Apply a single validation message to the error collection.
    private mutating func applyMessage(_ msg: ValidationMessage) {
        switch msg {
        case .field(let field, let message):
            errors.add(field: field, message)
        case .model(let message):
            errors.add(message)
        }
    }

    /// Returns the data if valid, throws ``ValidationErrors`` if not.
    ///
    /// ```swift
    /// let validData = try changeset.requireValid()
    /// ```
    public func requireValid() throws -> T {
        guard isValid else { throw errors }
        return data
    }
}
