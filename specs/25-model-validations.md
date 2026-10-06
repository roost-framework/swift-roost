# Spec: Model Validations

**Status:** Proposed
**Date:** 2026-04-07
**Depends on:** Roost core (spec 01), Spectro ORM, Auth & Scope System (spec 22)

---

## 1. Goal

Roost lacks a model validation system. Developers must manually validate data before saving to the database, which leads to inconsistent validation logic and potential data integrity issues. Phoenix solved this with changesets - a powerful validation system that:

1. **Separates validation from persistence** - Validate before saving
2. **Supports complex rules** - Multi-field, async, and database-dependent validation
3. **Provides clear errors** - Field-level and model-level error messages
4. **Works with associations** - Validate related records exist
5. **Integrates with scopes** - Support scoped validation (uniqueness per user)

This spec implements a **Swift-native changeset validation system** inspired by Phoenix Ecto but adapted for Swift's type system.

---

## 2. Scope

### 2.1 Changeset Protocol

#### 2.1.1 Changeset Definition

```swift
// In Sources/Roost/Validations/Changeset.swift

public protocol Changeset: Sendable {
    associatedtype Model: Schema
    associatedtype Value: Codable
    
    /// The original model (if updating existing record)
    var original: Model? { get }
    
    /// The changes to apply
    var changes: [String: Any] { get }
    
    /// Validation errors
    var errors: ValidationError { get }
    
    /// The validation action (create/update/delete)
    var action: ChangesetAction { get }
    
    /// Check if changeset is valid
    var isValid: Bool { get }
    
    /// Add a validation error
    mutating func addError(_ error: ValidationError)
    
    /// Validate with rules
    mutating func validate(_ database: SpectroClient? = nil) async throws
}

public enum ChangesetAction {
    case create
    case update
    case delete
}

public struct ValidationError: Sendable {
    public let fieldErrors: [String: [String]]
    public let modelErrors: [String]
    
    public init() {
        self.fieldErrors = [:]
        self.modelErrors = []
    }
    
    public var isEmpty: Bool {
        fieldErrors.isEmpty && modelErrors.isEmpty
    }
    
    public mutating func add(field: String, error: String) {
        if fieldErrors[field] == nil {
            fieldErrors[field] = []
        }
        fieldErrors[field]?.append(error)
    }
    
    public mutating func add(modelError: String) {
        modelErrors.append(modelError)
    }
}
```

#### 2.1.2 Generic Changeset Implementation

```swift
// In Sources/Roost/Validations/GenericChangeset.swift

public struct GenericChangeset<M: Schema, V: Codable = M>: Changeset, Sendable {
    public let original: M?
    public var changes: [String: Any]
    public var errors: ValidationError
    public let action: ChangesetAction
    public var validators: [any ValidatorProtocol<M>]
    
    public init(
        original: M? = nil,
        changes: [String: Any] = [:],
        action: ChangesetAction = .create
    ) {
        self.original = original
        self.changes = changes
        self.errors = ValidationError()
        self.action = action
        self.validators = []
    }
    
    public var isValid: Bool {
        errors.isEmpty
    }
    
    public mutating func addError(_ error: ValidationError) {
        self.errors = error
    }
    
    /// Apply changes to model
    public func apply() throws -> M {
        guard isValid else {
            throw ValidationError.invalid(self.errors)
        }
        
        var model = original ?? M()
        
        for (key, value) in changes {
            try model.setValue(value, forKey: key)
        }
        
        return model
    }
    
    /// Run all validations
    public mutating func validate(_ database: SpectroClient? = nil) async throws {
        // Reset errors
        errors = ValidationError()
        
        // Run all validators
        for validator in validators {
            try await validator.validate(
                changeset: &self,
                database: database
            )
        }
        
        // Check if valid
        if !isValid {
            throw ValidationError.invalid(errors)
        }
    }
}
```

---

### 2.2 Built-in Validators

#### 2.2.1 Validator Protocol

```swift
// In Sources/Roost/Validations/Validator.swift

public protocol ValidatorProtocol<Model: Schema>: Sendable {
    func validate(
        changeset: inout GenericChangeset<Model, any Codable>,
        database: SpectroClient?
    ) async throws
}
```

#### 2.2.2 Required Validator

```swift
// In Sources/Roost/Validations/RequiredValidator.swift

public struct RequiredValidator: ValidatorProtocol<any Schema>, Sendable {
    let fields: [String]
    
    public init(fields: [String]) {
        self.fields = fields
    }
    
    public init(_ fields: String...) {
        self.fields = fields
    }
    
    public func validate(
        changeset: inout GenericChangeset<any Schema, any Codable>,
        database: SpectroClient?
    ) async throws {
        for field in fields {
            if let value = changeset.changes[field] {
                if let stringValue = value as? String, stringValue.isEmpty {
                    changeset.errors.add(field: field, error: "can't be blank")
                } else if let optionalValue = value as? OptionalAny, optionalValue.isNil {
                    changeset.errors.add(field: field, error: "can't be blank")
                }
            } else if changeset.original == nil {
                // New record, field is missing
                changeset.errors.add(field: field, error: "can't be blank")
            }
        }
    }
}
```

#### 2.2.3 Format Validator

```swift
// In Sources/Roost/Validations/FormatValidator.swift

public struct FormatValidator: ValidatorProtocol<any Schema>, Sendable {
    let field: String
    let pattern: Regex<AnyRegexOutput>
    let message: String?
    
    public init(field: String, pattern: String, message: String? = nil) throws {
        self.field = field
        self.pattern = try Regex(pattern)
        self.message = message
    }
    
    public func validate(
        changeset: inout GenericChangeset<any Schema, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let value = changeset.changes[field] as? String else {
            return
        }
        
        if !(value.contains(pattern)) {
            let errorMessage = message ?? "has invalid format"
            changeset.errors.add(field: field, error: errorMessage)
        }
    }
}

// Convenience constructors
extension FormatValidator {
    /// Email format validation
    public static func email(field: String) throws -> FormatValidator {
        try FormatValidator(
            field: field,
            pattern: "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$",
            message: "is not a valid email"
        )
    }
    
    /// URL format validation
    public static func url(field: String) throws -> FormatValidator {
        try FormatValidator(
            field: field,
            pattern: "^https?://.+",
            message: "is not a valid URL"
        )
    }
    
    /// UUID format validation
    public static func uuid(field: String) throws -> FormatValidator {
        try FormatValidator(
            field: field,
            pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            message: "is not a valid UUID"
        )
    }
}
```

#### 2.2.4 Length Validator

```swift
// In Sources/Roost/Validations/LengthValidator.swift

public struct LengthValidator: ValidatorProtocol<any Schema>, Sendable {
    let field: String
    let min: Int?
    let max: Int?
    let exact: Int?
    
    public init(field: String, min: Int? = nil, max: Int? = nil, exact: Int? = nil) {
        self.field = field
        self.min = min
        self.max = max
        self.exact = exact
    }
    
    public func validate(
        changeset: inout GenericChangeset<any Schema, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let value = changeset.changes[field] as? String else {
            return
        }
        
        let length = value.count
        
        if let exact = exact, length != exact {
            changeset.errors.add(field: field, error: "should be \(exact) characters")
        } else {
            if let min = min, length < min {
                changeset.errors.add(field: field, error: "should be at least \(min) characters")
            }
            
            if let max = max, length > max {
                changeset.errors.add(field: field, error: "should be at most \(max) characters")
            }
        }
    }
}
```

#### 2.2.5 Inclusion/Exclusion Validator

```swift
// In Sources/Roost/Validations/InclusionValidator.swift

public struct InclusionValidator<T: Equatable & Sendable>: ValidatorProtocol<any Schema>, Sendable {
    let field: String
    let values: [T]
    let message: String?
    
    public init(field: String, in values: [T], message: String? = nil) {
        self.field = field
        self.values = values
        self.message = message
    }
    
    public func validate(
        changeset: inout GenericChangeset<any Schema, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let value = changeset.changes[field] as? T else {
            return
        }
        
        if !values.contains(value) {
            let errorMessage = message ?? "is not included in the list"
            changeset.errors.add(field: field, error: errorMessage)
        }
    }
}

public struct ExclusionValidator<T: Equatable & Sendable>: ValidatorProtocol<any Schema>, Sendable {
    let field: String
    let values: [T]
    let message: String?
    
    public init(field: String, notIn values: [T], message: String? = nil) {
        self.field = field
        self.values = values
        self.message = message
    }
    
    public func validate(
        changeset: inout GenericChangeset<any Schema, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let value = changeset.changes[field] as? T else {
            return
        }
        
        if values.contains(value) {
            let errorMessage = message ?? "is reserved"
            changeset.errors.add(field: field, error: errorMessage)
        }
    }
}
```

---

### 2.3 Custom Validators

#### 2.3.1 Custom Validator Protocol

```swift
// In Sources/Roost/Validations/CustomValidator.swift

public struct CustomValidator<Model: Schema>: ValidatorProtocol<Model>, Sendable {
    let field: String?
    let validation: (inout GenericChangeset<Model, any Codable>, SpectroClient?) async throws -> Void
    
    public init(
        field: String? = nil,
        _ validation: @escaping (inout GenericChangeset<Model, any Codable>, SpectroClient?) async throws -> Void
    ) {
        self.field = field
        self.validation = validation
    }
    
    public func validate(
        changeset: inout GenericChangeset<Model, any Codable>,
        database: SpectroClient?
    ) async throws {
        try await validation(&changeset, database)
    }
}
```

#### 2.3.2 Custom Validator Examples

```swift
// Custom validation example
extension CustomValidator where Model == User {
    /// Password strength validation
    public static func strongPassword(field: String = "password") -> CustomValidator<User> {
        CustomValidator(field: field) { changeset, _ in
            guard let password = changeset.changes[field] as? String else {
                return
            }
            
            if password.count < 8 {
                changeset.errors.add(field: field, error: "is too weak (minimum 8 characters)")
                return
            }
            
            // Check for uppercase, lowercase, number, special char
            let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
            let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
            let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil
            
            if !hasUppercase || !hasLowercase || !hasNumber {
                changeset.errors.add(field: field, error: "must include uppercase, lowercase, and number")
            }
        }
    }
    
    /// Age validation
    public static func adultAge(field: String = "age") -> CustomValidator<User> {
        CustomValidator(field: field) { changeset, _ in
            guard let age = changeset.changes[field] as? Int else {
                return
            }
            
            if age < 18 {
                changeset.errors.add(field: field, error: "must be 18 or older")
            }
        }
    }
}
```

---

### 2.4 Multi-field Validation

#### 2.4.1 Confirmation Validator

```swift
// In Sources/Roost/Validations/ConfirmationValidator.swift

public struct ConfirmationValidator: ValidatorProtocol<any Schema>, Sendable {
    let field: String
    let confirmationField: String
    
    public init(field: String, confirmationField: String) {
        self.field = field
        self.confirmationField = confirmationField
    }
    
    public convenience init(field: String) {
        self.init(field: field, confirmationField: "\(field)Confirmation")
    }
    
    public func validate(
        changeset: inout GenericChangeset<any Schema, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let value = changeset.changes[field] else {
            return
        }
        
        guard let confirmation = changeset.changes[confirmationField] else {
            changeset.errors.add(field: confirmationField, error: "can't be blank")
            return
        }
        
        if String(describing: value) != String(describing: confirmation) {
            changeset.errors.add(field: confirmationField, error: "doesn't match \(field)")
        }
    }
}
```

#### 2.4.2 Comparison Validator

```swift
// In Sources/Roost/Validations/ComparisonValidator.swift

public struct ComparisonValidator<T: Comparable & Sendable>: ValidatorProtocol<any Schema>, Sendable {
    let field: String
    let otherField: String
    let comparison: ComparisonType
    let message: String?
    
    public enum ComparisonType {
        case greaterThan
        case greaterThanOrEqual
        case lessThan
        case lessThanOrEqual
        case equal
        case notEqual
    }
    
    public init(field: String, otherField: String, comparison: ComparisonType, message: String? = nil) {
        self.field = field
        self.otherField = otherField
        self.comparison = comparison
        self.message = message
    }
    
    public func validate(
        changeset: inout GenericChangeset<any Schema, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let value = changeset.changes[field] as? T,
              let otherValue = changeset.changes[otherField] as? T else {
            return
        }
        
        let result: Bool
        
        switch comparison {
        case .greaterThan:
            result = value > otherValue
        case .greaterThanOrEqual:
            result = value >= otherValue
        case .lessThan:
            result = value < otherValue
        case .lessThanOrEqual:
            result = value <= otherValue
        case .equal:
            result = value == otherValue
        case .notEqual:
            result = value != otherValue
        }
        
        if !result {
            let errorMessage = message ?? "must be \(comparison) \(otherField)"
            changeset.errors.add(field: field, error: errorMessage)
        }
    }
}
```

---

### 2.5 Async Database Validation

#### 2.5.1 Uniqueness Validator

```swift
// In Sources/Roost/Validations/UniquenessValidator.swift

public struct UniquenessValidator<Model: Schema>: ValidatorProtocol<Model>, Sendable {
    let field: String
    let scope: [String: Any]?
    let caseSensitive: Bool
    
    public init(field: String, scope: [String: Any]? = nil, caseSensitive: Bool = true) {
        self.field = field
        self.scope = scope
        self.caseSensitive = caseSensitive
    }
    
    public func validate(
        changeset: inout GenericChangeset<Model, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let database = database else {
            changeset.errors.add(modelError: "database connection required for uniqueness validation")
            return
        }
        
        guard let value = changeset.changes[field] else {
            return
        }
        
        var query = database.query(Model.self)
        
        // Add field comparison
        if caseSensitive {
            query = query.where(\(field) == value as! String)
        } else {
            // Case-insensitive comparison
            query = query.where("\(field) ILIKE %@", [value])
        }
        
        // Add scope constraints
        if let scope = scope {
            for (key, scopeValue) in scope {
                query = query.where("\(key) = %@", [scopeValue])
            }
        }
        
        // Exclude current record if updating
        if let original = changeset.original, let id = original.id {
            query = query.where(\.id != id)
        }
        
        let existing = try await query.first()
        
        if existing != nil {
            changeset.errors.add(field: field, error: "has already been taken")
        }
    }
}
```

#### 2.5.2 Association Validator

```swift
// In Sources/Roost/Validations/AssociationValidator.swift

public struct AssociationValidator<Model: Schema>: ValidatorProtocol<Model>, Sendable {
    let field: String
    let associatedModel: any Schema.Type
    let message: String?
    
    public init(field: String, associatedModel: any Schema.Type, message: String? = nil) {
        self.field = field
        self.associatedModel = associatedModel
        self.message = message
    }
    
    public func validate(
        changeset: inout GenericChangeset<Model, any Codable>,
        database: SpectroClient?
    ) async throws {
        guard let database = database else {
            changeset.errors.add(modelError: "database connection required for association validation")
            return
        }
        
        guard let value = changeset.changes[field] else {
            return
        }
        
        let exists = try await database.query(associatedModel)
            .where(\.id == value as! UUID)
            .first()
        
        if exists == nil {
            let errorMessage = message ?? "does not exist"
            changeset.errors.add(field: field, error: errorMessage)
        }
    }
}
```

#### 2.5.3 Constraint Validator

```swift
// In Sources/Roost/Validations/ConstraintValidator.swift

public struct ConstraintValidator<Model: Schema>: ValidatorProtocol<Model>, Sendable {
    let constraints: [String]
    
    public init(constraints: [String]) {
        self.constraints = constraints
    }
    
    public func validate(
        changeset: inout GenericChangeset<Model, any Codable>,
        database: SpectroClient?
    ) async throws {
        // This would check database constraints
        // Implementation depends on Spectro's constraint checking capabilities
        // For now, this is a placeholder for future enhancement
    }
}
```

---

### 2.6 Usage Examples

#### 2.6.1 Model with Validations

```swift
// Models/User.swift
import Roost
import SpectroKit

@Schema("users")
struct User {
    @ID var id: UUID
    @ForeignKey var organizationId: UUID
    @Column var email: String
    @Column var hashedPassword: String
    @Column var name: String
    @Column var age: Int
    @Timestamp var createdAt: Date
    @Timestamp var updatedAt: Date
    
    /// Create a changeset for user creation
    static func changeset(
        email: String,
        password: String,
        passwordConfirmation: String,
        name: String,
        age: Int,
        organizationId: UUID
    ) -> GenericChangeset<User> {
        var changeset = GenericChangeset<User>(
            changes: [
                "email": email,
                "hashedPassword": password,
                "passwordConfirmation": passwordConfirmation,
                "name": name,
                "age": age,
                "organizationId": organizationId
            ],
            action: .create
        )
        
        // Add validators
        changeset.validators = [
            RequiredValidator("email", "name", "age", "hashedPassword"),
            try! FormatValidator.email(field: "email"),
            LengthValidator(field: "name", min: 2, max: 50),
            LengthValidator(field: "hashedPassword", min: 8),
            ConfirmationValidator(field: "hashedPassword"),
            CustomValidator<User>.strongPassword(field: "hashedPassword"),
            CustomValidator<User>.adultAge(field: "age"),
            UniquenessValidator(
                field: "email",
                scope: ["organizationId": organizationId]
            ),
            InclusionValidator(
                field: "age",
                in: [18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]
            )
        ]
        
        return changeset
    }
}
```

#### 2.6.2 Context Integration

```swift
// Contexts/UsersContext.swift
import Roost
import SpectroKit

extension UsersContext {
    /// Create a user with validation
    func createUser(
        email: String,
        password: String,
        passwordConfirmation: String,
        name: String,
        age: Int
    ) async throws -> User {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope
        
        // Create changeset
        var changeset = User.changeset(
            email: email,
            password: password,
            passwordConfirmation: passwordConfirmation,
            name: name,
            age: age,
            organizationId: userScope.organization!.id
        )
        
        // Validate
        try await changeset.validate(repo)
        
        // Hash password
        let hashedPassword = try Auth.hashPassword(password)
        changeset.changes["hashedPassword"] = hashedPassword
        
        // Apply changes
        let user = try changeset.apply()
        
        // Save to database
        return try await repo.save(user)
    }
    
    /// Update a user with validation
    func updateUser(_ user: User, changes: [String: Any]) async throws -> User {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        
        var changeset = GenericChangeset<User>(
            original: user,
            changes: changes,
            action: .update
        )
        
        changeset.validators = [
            try! FormatValidator.email(field: "email"),
            LengthValidator(field: "name", min: 2, max: 50),
            UniquenessValidator(
                field: "email",
                scope: ["organizationId": user.organizationId]
            )
        ]
        
        try await changeset.validate(repo)
        
        var updated = try changeset.apply()
        updated.updatedAt = Date()
        
        return try await repo.save(updated)
    }
}
```

#### 2.6.3 Route Integration

```swift
// Routes/UsersRoutes.swift
import Roost

extension RoostApp {
    var usersRoutes: [Route] {
        [
            POST("/users") { conn in
                let context = UsersContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                
                // Decode request
                let params = try conn.decode([String: Any].self)
                
                do {
                    let user = try await context.createUser(
                        email: params["email"] as! String,
                        password: params["password"] as! String,
                        passwordConfirmation: params["passwordConfirmation"] as! String,
                        name: params["name"] as! String,
                        age: params["age"] as! Int
                    )
                    
                    return Response.json(user.toJSON(), status: .created)
                } catch let error as ValidationError {
                    return Response.json([
                        "errors": error.fieldErrors,
                        "model": error.modelErrors
                    ], status: .unprocessableEntity)
                }
            }
        ]
    }
}
```

#### 2.6.4 Testing Integration

```swift
// Tests/UserValidationTests.swift
import Testing
@testable import MyApp

struct UserValidationTests {
    @Test("valid changeset passes validation")
    func validChangeset() async throws {
        let changeset = User.changeset(
            email: "test@example.com",
            password: "StrongPass123",
            passwordConfirmation: "StrongPass123",
            name: "Test User",
            age: 25,
            organizationId: UUID()
        )
        
        var validated = changeset
        try await validated.validate(nil)
        
        #expect(validated.isValid)
    }
    
    @Test("invalid email fails validation")
    func invalidEmail() async throws {
        let changeset = User.changeset(
            email: "not-an-email",
            password: "StrongPass123",
            passwordConfirmation: "StrongPass123",
            name: "Test User",
            age: 25,
            organizationId: UUID()
        )
        
        var validated = changeset
        try await validated.validate(nil)
        
        #expect(!validated.isValid)
        #expect(validated.errors.fieldErrors["email"]?.contains("is not a valid email") ?? false)
    }
    
    @Test("password mismatch fails validation")
    func passwordMismatch() async throws {
        let changeset = User.changeset(
            email: "test@example.com",
            password: "StrongPass123",
            passwordConfirmation: "DifferentPass123",
            name: "Test User",
            age: 25,
            organizationId: UUID()
        )
        
        var validated = changeset
        try await validated.validate(nil)
        
        #expect(!validated.isValid)
        #expect(validated.errors.fieldErrors["passwordConfirmation"]?.contains("doesn't match password") ?? false)
    }
    
    @Test("weak password fails validation")
    func weakPassword() async throws {
        let changeset = User.changeset(
            email: "test@example.com",
            password: "weak",
            passwordConfirmation: "weak",
            name: "Test User",
            age: 25,
            organizationId: UUID()
        )
        
        var validated = changeset
        try await validated.validate(nil)
        
        #expect(!validated.isValid)
        #expect(validated.errors.fieldErrors["hashedPassword"]?.contains("is too weak") ?? false)
    }
}
```

---

## 3. Acceptance Criteria

### 3.1 Changeset Protocol
- [ ] `Changeset` protocol defined with associated types
- [ ] `GenericChangeset` implements changeset protocol
- [ ] Changeset supports original model, changes, errors, and action
- [ ] `isValid` property checks if changeset has no errors
- [ ] `apply()` method applies changes to model
- [ ] `validate()` method runs all validators
- [ ] Changeset is Sendable and thread-safe

### 3.2 Error System
- [ ] `ValidationError` struct with fieldErrors and modelErrors
- [ ] `add(field:error:)` adds field-specific error
- [ ] `add(modelError:)` adds model-level error
- [ ] `isEmpty` property checks if no errors
- [ ] Multiple errors per field supported
- [ ] Errors are Sendable and Codable

### 3.3 Built-in Validators
- [ ] `RequiredValidator` validates required fields
- [ ] `FormatValidator` validates field formats (email, URL, UUID)
- [ ] `LengthValidator` validates string length (min/max/exact)
- [ ] `InclusionValidator` validates field values in allowed set
- [ ] `ExclusionValidator` validates field values not in disallowed set
- [ ] All validators support async validation
- [ ] All validators are Sendable

### 3.4 Custom Validators
- [ ] `CustomValidator` protocol with closure-based validation
- [ ] Custom validators can access all changeset fields
- [ ] Custom validators support async operations
- [ ] Custom validators can add field or model errors
- [ ] Extension examples for common validations (password, age)

### 3.5 Multi-field Validation
- [ ] `ConfirmationValidator` validates field confirmation
- [ ] `ComparisonValidator` validates field comparisons
- [ ] Comparison types: greaterThan, lessThan, equal, etc.
- [ ] Multi-field validators work with async validation

### 3.6 Database Validation
- [ ] `UniquenessValidator` validates uniqueness via database query
- [ ] `UniquenessValidator` supports scoped validation
- [ ] `UniquenessValidator` excludes current record on update
- [ ] `AssociationValidator` validates associated records exist
- [ ] `ConstraintValidator` checks database constraints
- [ ] Database validators handle missing database connection gracefully

### 3.7 Integration
- [ ] Integration with Spectro ORM
- [ ] Integration with scope system (spec 22)
- [ ] Integration with context layer
- [ ] Integration with route handlers
- [ ] Error responses in JSON format
- [ ] Validation errors renderable in views

### 3.8 Testing Support
- [ ] Test helpers for validation
- [ ] Assertions for validation errors
- [ ] Test database isolation
- [ ] Mock database support for async validators
- [ ] Example test files included

---

## 4. Non-goals

- No built-in internationalization (i18n) for error messages
- No automatic form generation from validators
- No client-side validation generation
- No nested model validation (validate associations recursively)
- No validation groups (create vs update validators)
- No conditional validation (if/else based on field values)
- No validation contexts (different rules for different contexts)
- No database constraint introspection (auto-generate validators from schema)
- No validation UI or management interface
- No validation rule inheritance or composition
- No real-time validation (validation on keystroke)
- No validation caching or performance optimization

---

## 5. Dependencies

- **Spectro ORM** - For database operations in validators
- **Auth & Scope System (spec 22)** - For scoped validation
- **swift-crypto** - For password hashing in validation examples
- **Swift concurrency** - For async validation support

---

## 6. Migration Notes

This spec introduces a new validation system. Migration guide for existing apps:

1. **New apps** - Start using changesets immediately
2. **Existing validation** - Gradually migrate to changeset system
3. **Backward compatibility** - Old validation code continues to work
4. **Performance** - Database validators require queries, use caching

To migrate existing validation code:

```swift
// Before: Manual validation
func createUser(params: [String: Any]) throws -> User {
    guard let email = params["email"] as? String else {
        throw ValidationError("email is required")
    }
    
    // Manual validation...
    return user
}

// After: Changeset validation
func createUser(params: [String: Any]) async throws -> User {
    var changeset = User.changeset(from: params)
    try await changeset.validate(database)
    return try changeset.apply()
}
```

---

## 7. Future Enhancements

Possible follow-up features:

- **Internationalization** - Translate error messages based on locale
- **Validation groups** - Different validators for create vs update
- **Conditional validation** - Apply validators based on field values
- **Nested validation** - Validate associated models recursively
- **Auto-form generation** - Generate HTML forms from validators
- **Client-side validation** - Generate JavaScript validators
- **Constraint introspection** - Auto-generate validators from database schema
- **Validation caching** - Cache uniqueness validation results
- **Performance optimization** - Batch database validations
- **Validation UI** - Web interface for managing validation rules
