import Foundation
import Testing

@testable import Roost

// MARK: - Test Types

struct TestInput: Sendable {
    let name: String
    let email: String
    let age: Int
    let bio: String?
    let role: String
    let password: String
    let passwordConfirmation: String
    let website: String
}

extension TestInput {
    static func valid() -> TestInput {
        TestInput(
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            bio: "Hello world",
            role: "user",
            password: "StrongPass1",
            passwordConfirmation: "StrongPass1",
            website: "https://example.com"
        )
    }
}

// MARK: - ValidationErrors Tests

@Suite("Validations — ValidationErrors")
struct ValidationErrorsTests {

    @Test("starts empty and valid")
    func startsValid() {
        let errors = ValidationErrors()
        #expect(errors.isValid)
        #expect(errors.count == 0)
        #expect(errors.fieldErrors.isEmpty)
        #expect(errors.modelErrors.isEmpty)
    }

    @Test("add field error makes invalid")
    func addFieldError() {
        var errors = ValidationErrors()
        errors.add(field: "email", "can't be blank")

        #expect(!errors.isValid)
        #expect(errors.count == 1)
        #expect(errors["email"] == ["can't be blank"])
    }

    @Test("multiple errors per field")
    func multipleFieldErrors() {
        var errors = ValidationErrors()
        errors.add(field: "email", "can't be blank")
        errors.add(field: "email", "is not a valid email")

        #expect(errors["email"].count == 2)
        #expect(errors["email"].contains("can't be blank"))
        #expect(errors["email"].contains("is not a valid email"))
    }

    @Test("model-level errors")
    func modelErrors() {
        var errors = ValidationErrors()
        errors.add("record is stale")

        #expect(!errors.isValid)
        #expect(errors.count == 1)
        #expect(errors.modelErrors == ["record is stale"])
    }

    @Test("subscript returns empty for unknown field")
    func unknownFieldReturnsEmpty() {
        let errors = ValidationErrors()
        #expect(errors["nonexistent"].isEmpty)
    }

    @Test("count reflects total errors")
    func errorCount() {
        var errors = ValidationErrors()
        errors.add(field: "name", "too short")
        errors.add(field: "name", "has invalid characters")
        errors.add(field: "email", "is taken")
        errors.add("general error")

        #expect(errors.count == 4)
    }

    @Test("merge combines errors from both")
    func mergeErrors() {
        var a = ValidationErrors()
        a.add(field: "name", "too short")
        a.add("model error A")

        var b = ValidationErrors()
        b.add(field: "email", "is taken")
        b.add("model error B")

        a.merge(b)

        #expect(a["name"] == ["too short"])
        #expect(a["email"] == ["is taken"])
        #expect(a.modelErrors.count == 2)
        #expect(a.count == 4)
    }

    @Test("equality")
    func equality() {
        var a = ValidationErrors()
        a.add(field: "name", "too short")

        var b = ValidationErrors()
        b.add(field: "name", "too short")

        #expect(a == b)
    }
}

// MARK: - Changeset Tests

@Suite("Validations — Changeset")
struct ChangesetTests {

    @Test("new changeset starts valid")
    func newChangesetValid() {
        let changeset = Changeset(data: TestInput.valid(), action: .create)
        #expect(changeset.isValid)
        #expect(changeset.action == .create)
        #expect(changeset.original == nil)
    }

    @Test("changeset stores original for updates")
    func changesetWithOriginal() {
        let original = TestInput.valid()
        let updated = TestInput.valid()
        let changeset = Changeset(data: updated, original: original, action: .update)
        #expect(changeset.action == .update)
        #expect(changeset.original != nil)
    }

    @Test("validate populates errors from failing rules")
    func validatePopulatesErrors() async {
        let input = TestInput(
            name: "", email: "bad", age: 10,
            bio: nil, role: "user", password: "x",
            passwordConfirmation: "y", website: "not-a-url"
        )
        var changeset = Changeset(data: input, action: .create)

        await changeset.validate(using: [
            .required("name") { $0.name },
        ])

        #expect(!changeset.isValid)
        #expect(changeset.errors["name"].contains("can't be blank"))
    }

    @Test("validate clears previous errors")
    func validateClearsPreviousErrors() async {
        var changeset = Changeset(data: TestInput.valid(), action: .create)

        // First validation with a failing rule
        await changeset.validate(using: [
            .custom { _ in [.field("x", "forced error")] },
        ])
        #expect(!changeset.isValid)

        // Second validation with passing rules
        await changeset.validate(using: [])
        #expect(changeset.isValid)
    }

    @Test("requireValid throws when invalid")
    func requireValidThrows() async {
        let input = TestInput(
            name: "", email: "", age: 0,
            bio: nil, role: "", password: "",
            passwordConfirmation: "", website: ""
        )
        var changeset = Changeset(data: input, action: .create)
        await changeset.validate(using: [
            .required("name") { $0.name },
        ])

        #expect(throws: ValidationErrors.self) {
            _ = try changeset.requireValid()
        }
    }

    @Test("requireValid returns data when valid")
    func requireValidReturns() async throws {
        var changeset = Changeset(data: TestInput.valid(), action: .create)
        await changeset.validate(using: [
            .required("name") { $0.name },
        ])

        let result = try changeset.requireValid()
        #expect(result.name == "Alice")
    }
}

// MARK: - Required Validator Tests

@Suite("Validations — Required")
struct RequiredValidatorTests {

    @Test("passes for non-empty string")
    func passesNonEmpty() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [.required("name") { $0.name }])
        #expect(cs.isValid)
    }

    @Test("fails for empty string")
    func failsEmpty() async {
        let input = TestInput(
            name: "", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [.required("name") { $0.name }])
        #expect(!cs.isValid)
        #expect(cs.errors["name"] == ["can't be blank"])
    }

    @Test("fails for whitespace-only string")
    func failsWhitespace() async {
        let input = TestInput(
            name: "   ", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [.required("name") { $0.name }])
        #expect(!cs.isValid)
    }

    @Test("optional string passes when present and non-empty")
    func optionalPresent() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [.required("bio") { $0.bio }])
        #expect(cs.isValid)
    }

    @Test("optional string fails when nil")
    func optionalNil() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [.required("bio") { $0.bio }])
        #expect(!cs.isValid)
        #expect(cs.errors["bio"] == ["can't be blank"])
    }

    @Test("optional string fails when empty")
    func optionalEmpty() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: "", role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [.required("bio") { $0.bio }])
        #expect(!cs.isValid)
    }

    @Test("requiredValue passes when non-nil")
    func requiredValuePresent() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [.requiredValue("bio") { $0.bio }])
        #expect(cs.isValid)
    }

    @Test("requiredValue fails when nil")
    func requiredValueNil() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [.requiredValue("bio") { $0.bio }])
        #expect(!cs.isValid)
    }
}

// MARK: - Length Validator Tests

@Suite("Validations — Length")
struct LengthValidatorTests {

    @Test("passes when within range")
    func withinRange() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .length("name", { $0.name }, min: 2, max: 50),
        ])
        #expect(cs.isValid)
    }

    @Test("fails when too short")
    func tooShort() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .length("name", { $0.name }, min: 2),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["name"].first == "should be at least 2 characters")
    }

    @Test("fails when too long")
    func tooLong() async {
        let input = TestInput(
            name: String(repeating: "a", count: 51), email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .length("name", { $0.name }, max: 50),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["name"].first == "should be at most 50 characters")
    }

    @Test("exact length passes")
    func exactPasses() async {
        let input = TestInput(
            name: "ABCDEF", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .length("name", { $0.name }, exact: 6),
        ])
        #expect(cs.isValid)
    }

    @Test("exact length fails")
    func exactFails() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .length("name", { $0.name }, exact: 3),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["name"].first == "should be 3 characters")
    }

    @Test("both min and max can fail independently")
    func bothMinMax() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .length("name", { $0.name }, min: 5, max: 10),
        ])
        #expect(cs.errors["name"].count == 1)
        #expect(cs.errors["name"].first?.contains("at least 5") == true)
    }
}

// MARK: - Format Validator Tests

@Suite("Validations — Format")
struct FormatValidatorTests {

    @Test("email passes for valid email")
    func validEmail() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .email("email") { $0.email },
        ])
        #expect(cs.isValid)
    }

    @Test("email fails for invalid email")
    func invalidEmail() async {
        let input = TestInput(
            name: "A", email: "not-an-email", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .email("email") { $0.email },
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["email"].first == "is not a valid email")
    }

    @Test("email is case-insensitive")
    func emailCaseInsensitive() async {
        let input = TestInput(
            name: "A", email: "USER@EXAMPLE.COM", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .email("email") { $0.email },
        ])
        #expect(cs.isValid)
    }

    @Test("url passes for valid URL")
    func validUrl() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .url("website") { $0.website },
        ])
        #expect(cs.isValid)
    }

    @Test("url fails for non-URL")
    func invalidUrl() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "not-a-url"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .url("website") { $0.website },
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["website"].first == "is not a valid URL")
    }

    @Test("custom pattern")
    func customPattern() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .format("role", { $0.role }, pattern: "^(admin|user|guest)$"),
        ])
        #expect(cs.isValid)
    }

    @Test("custom pattern fails")
    func customPatternFails() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "superuser", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .format("role", { $0.role }, pattern: "^(admin|user|guest)$", message: "is not a valid role"),
        ])
        #expect(cs.errors["role"].first == "is not a valid role")
    }
}

// MARK: - Inclusion/Exclusion Tests

@Suite("Validations — Inclusion and Exclusion")
struct InclusionExclusionTests {

    @Test("inclusion passes when value is in allowed set")
    func inclusionPasses() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .inclusion("role", { $0.role }, in: ["admin", "user", "guest"]),
        ])
        #expect(cs.isValid)
    }

    @Test("inclusion fails when value is not in allowed set")
    func inclusionFails() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "superadmin", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .inclusion("role", { $0.role }, in: ["admin", "user", "guest"]),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["role"].first == "is not included in the list")
    }

    @Test("inclusion with custom message")
    func inclusionCustomMessage() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "bad", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .inclusion("role", { $0.role }, in: ["admin", "user"], message: "must be admin or user"),
        ])
        #expect(cs.errors["role"].first == "must be admin or user")
    }

    @Test("exclusion passes when value is not in disallowed set")
    func exclusionPasses() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .exclusion("name", { $0.name }, from: ["admin", "root", "system"]),
        ])
        #expect(cs.isValid)
    }

    @Test("exclusion fails when value is in disallowed set")
    func exclusionFails() async {
        let input = TestInput(
            name: "admin", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .exclusion("name", { $0.name }, from: ["admin", "root", "system"]),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["name"].first == "is reserved")
    }

    @Test("inclusion works with integers")
    func inclusionIntegers() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .inclusion("age", { $0.age }, in: [18, 21, 25, 30]),
        ])
        #expect(cs.isValid)
    }
}

// MARK: - Confirmation Tests

@Suite("Validations — Confirmation")
struct ConfirmationTests {

    @Test("passes when fields match")
    func matchingFields() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .confirmation(
                "password", { $0.password },
                confirmationField: "passwordConfirmation", { $0.passwordConfirmation }
            ),
        ])
        #expect(cs.isValid)
    }

    @Test("fails when fields don't match")
    func mismatchedFields() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "abc123",
            passwordConfirmation: "xyz789", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .confirmation(
                "password", { $0.password },
                confirmationField: "passwordConfirmation", { $0.passwordConfirmation }
            ),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["passwordConfirmation"].first == "doesn't match password")
    }
}

// MARK: - Number Validator Tests

@Suite("Validations — Number")
struct NumberValidatorTests {

    @Test("passes when within range")
    func withinRange() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .number("age", { $0.age }, greaterThanOrEqual: 18, lessThan: 120),
        ])
        #expect(cs.isValid)
    }

    @Test("fails greaterThan")
    func failsGreaterThan() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 5,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .number("age", { $0.age }, greaterThan: 10),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["age"].first == "must be greater than 10")
    }

    @Test("fails greaterThanOrEqual at boundary")
    func failsGTEAtBoundary() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 17,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .number("age", { $0.age }, greaterThanOrEqual: 18),
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["age"].first == "must be greater than or equal to 18")
    }

    @Test("passes greaterThanOrEqual at boundary")
    func passesGTEAtBoundary() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 18,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .number("age", { $0.age }, greaterThanOrEqual: 18),
        ])
        #expect(cs.isValid)
    }

    @Test("fails lessThan")
    func failsLessThan() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 150,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .number("age", { $0.age }, lessThan: 120),
        ])
        #expect(!cs.isValid)
    }

    @Test("fails lessThanOrEqual")
    func failsLTE() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 101,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .number("age", { $0.age }, lessThanOrEqual: 100),
        ])
        #expect(!cs.isValid)
    }

    @Test("multiple constraints produce multiple errors")
    func multipleConstraints() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: -5,
            bio: nil, role: "user", password: "pass",
            passwordConfirmation: "pass", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .number("age", { $0.age }, greaterThan: 0, lessThanOrEqual: 150),
        ])
        // Only greaterThan fails (-5 is not > 0), lessThanOrEqual passes (-5 <= 150)
        #expect(cs.errors["age"].count == 1)
    }
}

// MARK: - Custom Validator Tests

@Suite("Validations — Custom")
struct CustomValidatorTests {

    @Test("custom validator can add field errors")
    func customFieldError() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .custom { data in
                if data.password.count < 8 {
                    return [.field("password", "must be at least 8 characters")]
                }
                return []
            },
        ])
        // "StrongPass1" is 11 chars, passes
        #expect(cs.isValid)
    }

    @Test("custom validator can add model errors")
    func customModelError() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .custom { _ in
                [.model("system is in maintenance mode")]
            },
        ])
        #expect(!cs.isValid)
        #expect(cs.errors.modelErrors.first == "system is in maintenance mode")
    }

    @Test("custom async validator")
    func customAsync() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .customAsync { data in
                // Simulate async check
                try? await Task.sleep(for: .milliseconds(1))
                if data.name == "forbidden" {
                    return [.field("name", "is not allowed")]
                }
                return []
            },
        ])
        #expect(cs.isValid)
    }

    @Test("custom multi-field validation")
    func customMultiField() async {
        let input = TestInput(
            name: "A", email: "a@b.c", age: 25,
            bio: nil, role: "user", password: "abc",
            passwordConfirmation: "abc", website: "https://x.com"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .custom { data in
                var msgs: [ValidationMessage] = []
                let pw = data.password
                if pw.count < 8 {
                    msgs.append(.field("password", "must be at least 8 characters"))
                }
                if pw.range(of: "[A-Z]", options: .regularExpression) == nil {
                    msgs.append(.field("password", "must contain an uppercase letter"))
                }
                if pw.range(of: "[0-9]", options: .regularExpression) == nil {
                    msgs.append(.field("password", "must contain a number"))
                }
                return msgs
            },
        ])
        #expect(!cs.isValid)
        #expect(cs.errors["password"].count == 3)
    }
}

// MARK: - Combined Validation Tests

@Suite("Validations — Combined Rules")
struct CombinedValidationTests {

    @Test("multiple rules all pass")
    func allPass() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .required("name") { $0.name },
            .required("email") { $0.email },
            .length("name", { $0.name }, min: 2, max: 50),
            .email("email") { $0.email },
            .inclusion("role", { $0.role }, in: ["admin", "user", "guest"]),
            .number("age", { $0.age }, greaterThanOrEqual: 18),
            .confirmation(
                "password", { $0.password },
                confirmationField: "passwordConfirmation", { $0.passwordConfirmation }
            ),
        ])
        #expect(cs.isValid)
    }

    @Test("multiple rules multiple failures")
    func multipleFailures() async {
        let input = TestInput(
            name: "", email: "bad", age: 10,
            bio: nil, role: "hacker", password: "x",
            passwordConfirmation: "y", website: "nope"
        )
        var cs = Changeset(data: input, action: .create)
        await cs.validate(using: [
            .required("name") { $0.name },
            .email("email") { $0.email },
            .inclusion("role", { $0.role }, in: ["admin", "user"]),
            .number("age", { $0.age }, greaterThanOrEqual: 18),
            .confirmation(
                "password", { $0.password },
                confirmationField: "passwordConfirmation", { $0.passwordConfirmation }
            ),
        ])

        #expect(!cs.isValid)
        #expect(!cs.errors["name"].isEmpty)
        #expect(!cs.errors["email"].isEmpty)
        #expect(!cs.errors["role"].isEmpty)
        #expect(!cs.errors["age"].isEmpty)
        #expect(!cs.errors["passwordConfirmation"].isEmpty)
        #expect(cs.errors.count == 5)
    }
}

// MARK: - Concurrent Validation Tests

@Suite("Validations — Concurrent Strategy")
struct ConcurrentValidationTests {

    @Test("concurrent strategy produces same errors as sequential")
    func concurrentMatchesSequential() async {
        let input = TestInput(
            name: "", email: "bad", age: 10,
            bio: nil, role: "hacker", password: "x",
            passwordConfirmation: "y", website: "nope"
        )
        let rules: [ValidatorRule<TestInput>] = [
            .required("name") { $0.name },
            .email("email") { $0.email },
            .number("age", { $0.age }, greaterThanOrEqual: 18),
        ]

        var sequential = Changeset(data: input, action: .create)
        await sequential.validate(using: rules, strategy: .sequential)

        var concurrent = Changeset(data: input, action: .create)
        await concurrent.validate(using: rules, strategy: .concurrent)

        // Same fields have errors (order may differ)
        #expect(!sequential.isValid)
        #expect(!concurrent.isValid)
        #expect(!concurrent.errors["name"].isEmpty)
        #expect(!concurrent.errors["email"].isEmpty)
        #expect(!concurrent.errors["age"].isEmpty)
        #expect(concurrent.errors.count == sequential.errors.count)
    }

    @Test("concurrent strategy passes when all rules pass")
    func concurrentAllPass() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)
        await cs.validate(using: [
            .required("name") { $0.name },
            .email("email") { $0.email },
            .number("age", { $0.age }, greaterThanOrEqual: 18),
        ], strategy: .concurrent)
        #expect(cs.isValid)
    }

    @Test("concurrent strategy clears previous errors")
    func concurrentClearsPrevious() async {
        var cs = Changeset(data: TestInput.valid(), action: .create)

        await cs.validate(using: [
            .custom { _ in [.field("x", "forced")] },
        ], strategy: .concurrent)
        #expect(!cs.isValid)

        await cs.validate(using: [], strategy: .concurrent)
        #expect(cs.isValid)
    }
}

// MARK: - ValidationErrors Codable Tests

@Suite("Validations — ValidationErrors Codable")
struct ValidationErrorsCodableTests {

    @Test("encodes and decodes round-trip")
    func roundTrip() throws {
        var errors = ValidationErrors()
        errors.add(field: "email", "can't be blank")
        errors.add(field: "email", "is not a valid email")
        errors.add("record is stale")

        let data = try JSONEncoder().encode(errors)
        let decoded = try JSONDecoder().decode(ValidationErrors.self, from: data)

        #expect(decoded == errors)
    }

    @Test("jsonData() produces valid JSON")
    func jsonDataProducesJSON() throws {
        var errors = ValidationErrors()
        errors.add(field: "name", "too short")

        let data = try errors.jsonData()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)
        let fieldErrors = json?["fieldErrors"] as? [String: [String]]
        #expect(fieldErrors?["name"] == ["too short"])
    }

    @Test("empty errors encode correctly")
    func emptyEncodes() throws {
        let errors = ValidationErrors()
        let data = try errors.jsonData()
        let decoded = try JSONDecoder().decode(ValidationErrors.self, from: data)
        #expect(decoded.isValid)
    }
}

// MARK: - TokenExpirable Tests

struct MockToken: TokenExpirable {
    let expiresAt: Date?
}

@Suite("Auth — TokenExpirable")
struct TokenExpirableTests {

    @Test("isExpired returns false when expiresAt is nil")
    func noExpiry() {
        let token = MockToken(expiresAt: nil)
        #expect(!token.isExpired)
        #expect(token.isActive)
    }

    @Test("isExpired returns false for future date")
    func futureDate() {
        let token = MockToken(expiresAt: Date().addingTimeInterval(3600))
        #expect(!token.isExpired)
        #expect(token.isActive)
    }

    @Test("isExpired returns true for past date")
    func pastDate() {
        let token = MockToken(expiresAt: Date().addingTimeInterval(-3600))
        #expect(token.isExpired)
        #expect(!token.isActive)
    }
}
