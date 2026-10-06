import Foundation

/// A parsed field from `name:type` CLI syntax.
///
/// Supports modifiers:
///   - `?` suffix for optional: `bio:text?`
///   - `[]` suffix for arrays: `tags:string[]`
///   - `reference` type for FKs: `post:reference`
///   - Legacy modifier syntax: `user_id:uuid:references`
struct ParsedField {
    let name: String
    let type: FieldType
    let isOptional: Bool
    let isReference: Bool
    let isArray: Bool

    /// The Swift property name in camelCase.
    /// For references without `_id` suffix, appends `Id` (e.g. `post` → `postId`).
    var swiftName: String {
        let base = toCamelCase(name)
        if isReference && !name.hasSuffix("_id") && !name.hasSuffix("Id") {
            return base + "Id"
        }
        return base
    }

    /// The database column name in snake_case.
    /// For references without `_id` suffix, appends `_id` (e.g. `post` → `post_id`).
    var columnName: String {
        let base = toSnakeCase(name)
        if isReference && !base.hasSuffix("_id") {
            return base + "_id"
        }
        return base
    }

    /// The Swift type string (e.g. "String", "UUID?", "[String]").
    var swiftType: String {
        if isReference {
            return isOptional ? "UUID?" : "UUID"
        }
        if isArray {
            return isOptional ? "[\(type.swiftType)]?" : "[\(type.swiftType)]"
        }
        let base = type.swiftType
        return isOptional ? "\(base)?" : base
    }

    /// The Postgres column type (e.g. "TEXT", "UUID", "BIGINT[]").
    var postgresType: String {
        if isReference { return "UUID" }
        if isArray { return "\(type.postgresType)[]" }
        return type.postgresType
    }

    /// The Spectro property wrapper to use.
    var wrapper: String {
        if isReference { return "@ForeignKey" }
        return "@Column"
    }

    /// The SQL column definition for CREATE TABLE.
    var sqlDefinition: String {
        var parts = ["\"\(columnName)\" \(postgresType)"]
        if !isOptional {
            parts.append("NOT NULL")
        }
        if let defaultValue = type.defaultValue, !isOptional, !isReference, !isArray {
            parts.append("DEFAULT \(defaultValue)")
        }
        if isReference {
            let baseName: String
            if columnName.hasSuffix("_id") {
                baseName = String(columnName.dropLast(3))
            } else {
                baseName = columnName
            }
            let refTable = pluralize(baseName)
            parts.append("REFERENCES \"\(refTable)\"(\"id\")")
        }
        return parts.joined(separator: " ")
    }

    /// Human-readable label for forms (e.g. "firstName" → "FirstName").
    var displayName: String {
        swiftName.prefix(1).uppercased() + swiftName.dropFirst()
    }

    /// The HTML input type for form generation.
    var htmlInputType: String {
        if isReference { return "text" }
        switch type {
        case .string, .uuid: return "text"
        case .text, .json: return "textarea"
        case .int: return "number"
        case .double: return "number"
        case .bool: return "checkbox"
        case .date: return "datetime-local"
        case .data: return "file"
        }
    }

    /// Whether this field should be rendered as a textarea in forms.
    var isTextarea: Bool {
        type == .text || type == .json
    }

    /// Explicit reference fields are supplied by the caller too. The ownership
    /// key from --scope is separate and is never included in this input list.
    var isFormField: Bool {
        true
    }
}

/// Supported CLI field types.
enum FieldType: String {
    case string
    case text
    case int
    case double
    case bool
    case uuid
    case date
    case json
    case data

    var swiftType: String {
        switch self {
        case .string: "String"
        case .text: "String"
        case .int: "Int"
        case .double: "Double"
        case .bool: "Bool"
        case .uuid: "UUID"
        case .date: "Date"
        case .json: "String"
        case .data: "Data"
        }
    }

    var postgresType: String {
        switch self {
        case .string: "TEXT"
        case .text: "TEXT"
        case .int: "BIGINT"
        case .double: "NUMERIC"
        case .bool: "BOOLEAN"
        case .uuid: "UUID"
        case .date: "TIMESTAMPTZ"
        case .json: "JSONB"
        case .data: "BYTEA"
        }
    }

    var defaultValue: String? {
        switch self {
        case .bool: "true"
        case .int: "0"
        case .double: "0"
        default: nil
        }
    }
}

/// Parses field strings from CLI arguments.
///
/// Supported formats:
///   - `name:type` — basic field
///   - `name:type?` — optional field
///   - `name:type[]` — array field (Postgres only)
///   - `name:reference` — foreign key (UUID + REFERENCES)
///   - `name:reference?` — optional foreign key
///   - `name:type:optional` — legacy optional syntax
///   - `name:uuid:references` — legacy reference syntax
enum FieldParser {
    static func validateTypeName(_ name: String) throws {
        guard name.wholeMatch(of: #/[A-Z][a-zA-Z0-9]*/#) != nil else {
            throw FieldParserError.invalidIdentifier(name)
        }
    }

    static func parse(_ args: [String]) throws -> [ParsedField] {
        let parsed = try args.map { arg in
            let parts = arg.split(separator: ":", maxSplits: 3).map(String.init)
            guard parts.count >= 2 else {
                throw FieldParserError.invalidFormat(arg)
            }

            let name = parts[0]
            let reserved = ["id", "createdAt", "updatedAt", "created_at", "updated_at", "class", "struct", "enum", "let", "var", "self", "default", "return", "switch", "case", "protocol", "import", "extension", "func", "static", "private", "public", "internal", "init", "deinit", "subscript", "repeat", "where", "in", "for", "while", "if", "else", "nil", "true", "false", "try", "throw", "throws"]
            guard name.wholeMatch(of: #/[a-z][a-zA-Z0-9_]*/#) != nil, !reserved.contains(name) else {
                throw FieldParserError.invalidIdentifier(name)
            }
            var typeStr = parts[1]

            // Check for ? suffix (optional)
            let optionalSuffix = typeStr.hasSuffix("?")
            if optionalSuffix { typeStr = String(typeStr.dropLast()) }

            // Check for [] suffix (array)
            let arraySuffix = typeStr.hasSuffix("[]")
            if arraySuffix { typeStr = String(typeStr.dropLast(2)) }

            // Check for reference type
            let isRefType = typeStr == "reference"
            if isRefType { typeStr = "uuid" }

            guard let type = FieldType(rawValue: typeStr) else {
                throw FieldParserError.unknownType(typeStr)
            }

            // Legacy modifier support (name:type:optional, name:uuid:references)
            let modifiers = Set(parts.dropFirst(2))

            return ParsedField(
                name: name,
                type: type,
                isOptional: optionalSuffix || modifiers.contains("optional"),
                isReference: isRefType || modifiers.contains("references"),
                isArray: arraySuffix
            )
        }
        guard Set(parsed.map(\.columnName)).count == parsed.count,
              Set(parsed.map(\.swiftName)).count == parsed.count else {
            throw FieldParserError.invalidIdentifier("duplicate field")
        }
        return parsed
    }
}

enum FieldParserError: Error, CustomStringConvertible {
    case invalidFormat(String)
    case unknownType(String)
    case invalidIdentifier(String)

    var description: String {
        switch self {
        case .invalidFormat(let s):
            "Invalid field format '\(s)'. Expected name:type (e.g. name:string)"
        case .unknownType(let t):
            "Unknown type '\(t)'. Valid types: string, text, int, double, bool, date, json, data, uuid, reference"
        case .invalidIdentifier(let name):
            "Invalid or reserved identifier '\(name)'. Use a Swift identifier; model and app names must start with an uppercase letter."
        }
    }
}

// MARK: - String Helpers

/// Converts "category_id" or "categoryId" to "categoryId".
func toCamelCase(_ input: String) -> String {
    let parts = input.split(separator: "_")
    guard let first = parts.first else { return input }
    return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

/// Converts "categoryId" or "category_id" to "category_id".
func toSnakeCase(_ input: String) -> String {
    if input.contains("_") { return input }
    return input
        .replacing(#/([a-z])([A-Z])/#) { "\($0.output.1)_\($0.output.2)" }
        .lowercased()
}

/// Simple English pluralization.
func pluralize(_ word: String) -> String {
    let lower = word.lowercased()

    // Irregular plurals
    let irregulars: [String: String] = [
        "person": "people", "child": "children", "man": "men",
        "woman": "women", "mouse": "mice", "goose": "geese",
        "tooth": "teeth", "foot": "feet", "datum": "data",
        "index": "indices", "matrix": "matrices", "vertex": "vertices",
        "ox": "oxen", "quiz": "quizzes", "status": "statuses",
    ]
    if let irregular = irregulars[lower] {
        // Preserve original casing of first char
        if word.first?.isUppercase == true {
            return irregular.prefix(1).uppercased() + irregular.dropFirst()
        }
        return irregular
    }

    // Already-plural patterns — don't double-pluralize
    let alreadyPlural = ["ies", "ves", "oes", "ses", "xes", "zes", "ches", "shes"]
    for suffix in alreadyPlural {
        if lower.hasSuffix(suffix) { return word }
    }

    // Words ending in "s" that are already plural (heuristic: 4+ chars ending in
    // a consonant + "s" that isn't "ss"/"us"/"is")
    if lower.hasSuffix("s") && !lower.hasSuffix("ss") && !lower.hasSuffix("us") && !lower.hasSuffix("is") && lower.count >= 4 {
        return word
    }

    // Standard English rules
    if lower.hasSuffix("ss") || lower.hasSuffix("sh") || lower.hasSuffix("ch") || lower.hasSuffix("x") || lower.hasSuffix("z") {
        return word + "es"
    }
    if lower.hasSuffix("us") {
        return String(word.dropLast(2)) + "i"  // cactus → cacti
    }
    if lower.hasSuffix("is") {
        return String(word.dropLast(2)) + "es"  // analysis → analyses
    }
    if lower.hasSuffix("y") && !lower.hasSuffix("ay") && !lower.hasSuffix("ey") && !lower.hasSuffix("oy") && !lower.hasSuffix("uy") {
        return String(word.dropLast()) + "ies"
    }
    if lower.hasSuffix("f") {
        return String(word.dropLast()) + "ves"  // leaf → leaves
    }
    if lower.hasSuffix("fe") {
        return String(word.dropLast(2)) + "ves"  // knife → knives
    }
    return word + "s"
}

/// Converts "DonutShop" to "donut_shop".
func toSnakeCaseFromPascal(_ input: String) -> String {
    input
        .replacing(#/([a-z])([A-Z])/#) { "\($0.output.1)_\($0.output.2)" }
        .lowercased()
}

/// Converts "post" to "Post".
func toPascalCase(_ input: String) -> String {
    input.split(separator: "_")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined()
}

/// Lowercases the first character: "Post" → "post", "PostComment" → "postComment".
func toLowerFirst(_ input: String) -> String {
    input.prefix(1).lowercased() + input.dropFirst()
}
