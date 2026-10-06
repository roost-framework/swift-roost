# Spec: CLI Generators

**Status:** Proposed
**Date:** 2026-04-07
**Depends on:** Roost core (spec 01), Spectro ORM, Auth & Scope System (spec 22), Database Migrations (spec 23)

---

## 1. Goal

Developers waste time writing boilerplate code for models, routes, contexts, and views. Rails and Phoenix solved this with generators that create complete CRUD resources from a single command. Roost needs a generator system that:

1. **Eliminates boilerplate** - Generate models, contexts, routes, and views automatically
2. **Follows conventions** - Enforce Roost best practices out of the box
3. **Supports workflows** - Generate HTML views, JSON APIs, or both
4. **Integrates with scopes** - All generated code is secure-by-default
5. **Works with existing tools** - Uses Spectro schemas, ESW templates, and migration system

This spec implements a **Rails/Phoenix-style generator system** with built-in Swift templates and multiple generator types.

---

## 2. Scope

### 2.1 Resource Generator

#### 2.1.1 Generator Commands

```bash
# Generate HTML resource with views
$ roost generate resource Post title:string body:text published:bool
      create  Models/Post.swift
      create  Contexts/PostsContext.swift
      create  Routes/PostsRoutes.swift
      create  Views/posts/index.esw
      create  Views/posts/show.esw
      create  Views/posts/new.esw
      create  Views/posts/edit.esw
      create  Migrations/20260407143000_create_posts.sql

# Generate JSON API resource
$ roost generate resource Comment --json post:reference body:text
      create  Models/Comment.swift
      create  Contexts/CommentsContext.swift
      create  Routes/CommentsRoutes.swift
      create  Migrations/20260407143100_create_comments.sql

# Generate both HTML and JSON
$ roost generate resource Tag --both name:string color:string
      create  Models/Tag.swift
      create  Contexts/TagsContext.swift
      create  Routes/TagsRoutes.swift
      create  Views/tags/index.esw
      create  Views/tags/show.esw
      create  Views/tags/new.esw
      create  Views/tags/edit.esw
      create  Routes/TagsApiRoutes.swift
      create  Migrations/20260407143200_create_tags.sql

# Generate model-only (no routes/views)
$ roost generate resource Category --model-only name:string parent:reference?
      create  Models/Category.swift
      create  Contexts/CategoriesContext.swift
      create  Migrations/20260407143300_create_categories.sql
```

#### 2.1.2 Field Type Syntax

Generators support field types with optional modifiers:

```bash
# Basic types
$ roost generate resource Post \
    title:string \
    body:text \
    rating:int \
    price:double \
    published:bool \
    publishedAt:date \
    metadata:json \
    attachment:data

# Optional fields
$ roost generate resource User \
    name:string \
    email:string \
    age:int? \
    bio:text?

# Foreign key references
$ roost generate resource Comment \
    post:reference \
    user:reference \
    body:text

# Array types (Postgres only)
$ roost generate resource Article \
    title:string \
    tags:string[] \
    scores:int[]
```

#### 2.1.3 Generated Model

```swift
// Models/Post.swift
import SpectroKit

@Schema("posts")
struct Post {
    @ID var id: UUID
    @ForeignKey var userId: UUID  // Auto-added for scoping
    @Column var title: String
    @Column var body: String
    @Column var published: Bool
    @Timestamp var createdAt: Date
    @Timestamp var updatedAt: Date
}
```

#### 2.1.4 Generated Context (Phoenix-Style)

```swift
// Contexts/PostsContext.swift
import Roost
import SpectroKit

struct PostsContext {
    let conn: Connection
    let scope: any AuthScope

    /// List all posts scoped to current user
    func listPosts() async throws -> [Post] {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        return try await repo.query(Post.self)
            .where(\.userId == userScope.user!.id)
            .all()
    }

    /// Get a specific post by ID, scoped to current user
    func getPost(id: UUID) async throws -> Post {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        guard let post = try await repo.query(Post.self)
            .where(\.userId == userScope.user!.id)
            .where(\.id == id)
            .first() else {
            throw AbortError(.notFound)
        }

        return post
    }

    /// Create a new post scoped to current user
    func createPost(_ post: Post) async throws -> Post {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        var created = post
        created.userId = userScope.user!.id

        return try await repo.save(created)
    }

    /// Update a post
    func updatePost(_ post: Post) async throws -> Post {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient

        var updated = post
        updated.updatedAt = Date()

        return try await repo.save(updated)
    }

    /// Delete a post
    func deletePost(_ post: Post) async throws {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient

        try await repo.delete(post)
    }

    /// List published posts (custom query)
    func listPublishedPosts() async throws -> [Post] {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        return try await repo.query(Post.self)
            .where(\.userId == userScope.user!.id)
            .where(\.published == true)
            .all()
    }
}
```

#### 2.1.5 Generated Routes (HTML)

```swift
// Routes/PostsRoutes.swift
import Roost

extension RoostApp {
    var postsRoutes: [Route] {
        [
            GET("/posts") { conn in
                let context = PostsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                let posts = try await context.listPosts()
                return Response.render("posts/index", ["posts": posts])
            },

            GET("/posts/:id") { conn in
                let context = PostsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                let post = try await context.getPost(id: conn.params["id"]!)
                return Response.render("posts/show", ["post": post])
            },

            GET("/posts/new") { conn in
                return Response.render("posts/new", [:])
            },

            POST("/posts") { conn in
                let context = PostsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                var post = try conn.decode(Post.self)
                let created = try await context.createPost(post)
                return Response.redirect(to: "/posts/\(created.id)")
            },

            GET("/posts/:id/edit") { conn in
                let context = PostsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                let post = try await context.getPost(id: conn.params["id"]!)
                return Response.render("posts/edit", ["post": post])
            },

            PUT("/posts/:id") { conn in
                let context = PostsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                var post = try await context.getPost(id: conn.params["id"]!)
                post = try conn.decode(Post.self)
                let updated = try await context.updatePost(post)
                return Response.redirect(to: "/posts/\(updated.id)")
            },

            DELETE("/posts/:id") { conn in
                let context = PostsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                let post = try await context.getPost(id: conn.params["id"]!)
                try await context.deletePost(post)
                return Response.redirect(to: "/posts")
            }
        ]
    }
}
```

#### 2.1.6 Generated Views (HTML)

```html
<!-- Views/posts/index.esw -->
<%!
var conn: Connection
var posts: [Post]
%>

<h1>Posts</h1>

<p><a href="/posts/new">New Post</a></p>

<ul>
<% for post in posts { %>
  <li>
    <strong><%= post.title %></strong>
    <small><%= post.createdAt %></small>
    <% if post.published { %>
      <span>✅ Published</span>
    <% } else { %>
      <span>📝 Draft</span>
    <% } %>
    <a href="/posts/<%= post.id %>">View</a>
    <a href="/posts/<%= post.id %>/edit">Edit</a>
  </li>
<% } %>
</ul>
```

```html
<!-- Views/posts/show.esw -->
<%!
var conn: Connection
var post: Post
%>

<h1><%= post.title %></h1>

<p><small>Created: <%= post.createdAt %></small></p>

<div>
  <%= post.body %>
</div>

<p>
  <a href="/posts">Back</a>
  <a href="/posts/<%= post.id %>/edit">Edit</a>
</p>

<form method="post" action="/posts/<%= post.id %>">
  <input type="hidden" name="_method" value="DELETE">
  <button type="submit">Delete</button>
</form>
```

```html
<!-- Views/posts/new.esw -->
<%!
var conn: Connection
var csrfToken: String
%>

<h1>New Post</h1>

<form method="post" action="/posts">
  <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">

  <label>
    Title
    <input type="text" name="title" required>
  </label>

  <label>
    Body
    <textarea name="body" required></textarea>
  </label>

  <label>
    <input type="checkbox" name="published">
    Published
  </label>

  <button type="submit">Create Post</button>
</form>

<p><a href="/posts">Back</a></p>
```

```html
<!-- Views/posts/edit.esw -->
<%!
var conn: Connection
var post: Post
var csrfToken: String
%>

<h1>Edit Post</h1>

<form method="post" action="/posts/<%= post.id %>">
  <input type="hidden" name="_method" value="PUT">
  <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">

  <label>
    Title
    <input type="text" name="title" value="<%= post.title %>" required>
  </label>

  <label>
    Body
    <textarea name="body" required><%= post.body %></textarea>
  </label>

  <label>
    <input type="checkbox" name="published" <%= post.published ? "checked" : "" %>>
    Published
  </label>

  <button type="submit">Update Post</button>
</form>

<p><a href="/posts/<%= post.id %>">Cancel</a></p>
```

#### 2.1.7 Generated Routes (JSON API)

```swift
// Routes/CommentsApiRoutes.swift
import Roost

extension RoostApp {
    var commentsApiRoutes: [Route] {
        [
            GET("/api/comments") { conn in
                let context = CommentsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                let comments = try await context.listComments()
                return Response.json(comments.map { $0.toJSON() })
            },

            GET("/api/comments/:id") { conn in
                let context = CommentsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                let comment = try await context.getComment(id: conn.params["id"]!)
                return Response.json(comment.toJSON())
            },

            POST("/api/comments") { conn in
                let context = CommentsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                var comment = try conn.decode(Comment.self)
                let created = try await context.createComment(comment)
                return Response.json(created.toJSON(), status: .created)
            },

            PUT("/api/comments/:id") { conn in
                let context = CommentsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                var comment = try await context.getComment(id: conn.params["id"]!)
                comment = try conn.decode(Comment.self)
                let updated = try await context.updateComment(comment)
                return Response.json(updated.toJSON())
            },

            DELETE("/api/comments/:id") { conn in
                let context = CommentsContext(conn: conn, scope: conn.assigns["current_scope"] as! UserScope)
                let comment = try await context.getComment(id: conn.params["id"]!)
                try await context.deleteComment(comment)
                return Response.status: .noContent
            }
        ]
    }
}
```

---

### 2.2 Model Generator

#### 2.2.1 Generator Commands

```bash
# Generate standalone model
$ roost generate model User name:string email:string age:int
      create  Models/User.swift
      create  Migrations/20260407144000_create_users.sql

# Generate model with references
$ roost generate model Book author:reference publisher:reference title:string isbn:string
      create  Models/Book.swift
      create  Migrations/20260407144100_create_books.sql

# Generate model with options
$ roost generate model Product name:string price:decimal? description:text? stock:int
      create  Models/Product.swift
      create  Migrations/20260407144200_create_products.sql
```

#### 2.2.2 Generated Model

```swift
// Models/Book.swift
import SpectroKit

@Schema("books")
struct Book {
    @ID var id: UUID
    @ForeignKey var authorId: UUID
    @ForeignKey var publisherId: UUID
    @Column var title: String
    @Column var isbn: String
    @Timestamp var createdAt: Date
    @Timestamp var updatedAt: Date
}
```

#### 2.2.3 Type Mapping

| Field Type | Swift Type | Postgres Type |
|------------|------------|---------------|
| `string` | `String` | `TEXT` |
| `text` | `String` | `TEXT` |
| `int` | `Int` | `BIGINT` |
| `double` | `Double` | `NUMERIC` |
| `bool` | `Bool` | `BOOLEAN` |
| `date` | `Date` | `TIMESTAMPTZ` |
| `json` | `String` | `JSONB` |
| `data` | `Data` | `BYTEA` |
| `uuid` | `UUID` | `UUID` |
| `reference` | `UUID` (FK) | `UUID` (FK) |
| `string[]` | `[String]` | `TEXT[]` |
| `int[]` | `[Int]` | `BIGINT[]` |

Optional types add `?` to Swift type and make column nullable.

---

### 2.3 Migration Generator

#### 2.3.1 Generator Commands

```bash
# Generate migration
$ roost generate migration AddAuthorIdToPosts
      create  Migrations/20260407145000_add_author_id_to_posts.sql

# Generate migration with change
$ roost generate migration AddIndexToEmails --change
      create  Migrations/20260407145100_add_index_to_emails.sql
```

#### 2.3.2 Generated Migration

```sql
-- Migration: AddAuthorIdToPosts
-- Created: 2026-04-07 14:50:00
-- Up: Add author_id foreign key to posts
-- Down: Remove author_id from posts

-- +Migrate UP
BEGIN;

ALTER TABLE "posts" ADD COLUMN "author_id" UUID;
ALTER TABLE "posts" ADD CONSTRAINT "posts_author_id_fkey"
  FOREIGN KEY ("author_id") REFERENCES "authors"("id") ON DELETE SET NULL;

CREATE INDEX "posts_author_id_index" ON "posts" ("author_id");

COMMIT;

-- -Migrate DOWN
BEGIN;

DROP INDEX IF EXISTS "posts_author_id_index";
ALTER TABLE "posts" DROP CONSTRAINT IF EXISTS "posts_author_id_fkey";
ALTER TABLE "posts" DROP COLUMN IF EXISTS "author_id";

COMMIT;
```

---

### 2.4 Context Generator

#### 2.4.1 Generator Commands

```bash
# Generate context for existing model
$ roost generate context Post
      create  Contexts/PostsContext.swift

# Generate context with custom methods
$ roost generate context User --methods active-admins
      create  Contexts/UsersContext.swift
```

#### 2.4.2 Generated Context

```swift
// Contexts/UsersContext.swift
import Roost
import SpectroKit

struct UsersContext {
    let conn: Connection
    let scope: any AuthScope

    /// List all users scoped to current organization
    func listUsers() async throws -> [User] {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        return try await repo.query(User.self)
            .where(\.organizationId == userScope.organization!.id)
            .all()
    }

    /// Get a specific user by ID, scoped to current organization
    func getUser(id: UUID) async throws -> User {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        guard let user = try await repo.query(User.self)
            .where(\.organizationId == userScope.organization!.id)
            .where(\.id == id)
            .first() else {
            throw AbortError(.notFound)
        }

        return user
    }

    /// Create a new user scoped to current organization
    func createUser(_ user: User) async throws -> User {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        var created = user
        created.organizationId = userScope.organization!.id

        return try await repo.save(created)
    }

    /// Update a user
    func updateUser(_ user: User) async throws -> User {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient

        var updated = user
        updated.updatedAt = Date()

        return try await repo.save(updated)
    }

    /// Delete a user
    func deleteUser(_ user: User) async throws {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient

        try await repo.delete(user)
    }
}
```

---

### 2.5 Template System

#### 2.5.1 Built-in Templates

```swift
// In Sources/RoostCLI/Templates/ModelTemplate.swift

public enum ModelTemplate {
    public static func render(
        name: String,
        table: String,
        fields: [FieldDefinition],
        scope: ScopeMetadata?
    ) -> String {
        let fieldDefinitions = fields.map { field in
            let optional = field.isOptional ? "?" : ""
            return "    @Column var \(field.name)\(optional): \(field.swiftType)"
        }.joined(separator: "\n")

        let scopeField = scope.map {
            "    @ForeignKey var \($0.schemaKey): \($0.schemaType)"
        } ?? ""

        return """
import SpectroKit

@Schema("\(table)")
struct \(name) {
\(scopeField)

\(fieldDefinitions)
    @Timestamp var createdAt: Date
    @Timestamp var updatedAt: Date
}
"""
    }
}

// In Sources/RoostCLI/Templates/ContextTemplate.swift

public enum ContextTemplate {
    public static func render(
        name: String,
        plural: String,
        table: String,
        fields: [FieldDefinition],
        scope: ScopeMetadata?
    ) -> String {
        let scopeQuery = scope.map { scope in
            """
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        return try await repo.query(\(name).self)
            .where(\\.\(scope.schemaKey) == userScope.user!.id)
"""
        } ?? """
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        return try await repo.query(\(name).self)
"""

        return """
import Roost
import SpectroKit

struct \(plural)Context {
    let conn: Connection
    let scope: any AuthScope

    /// List all \(plural.lowercased()) scoped to current user
    func list\(plural)() async throws -> [\(name)] {
\(scopeQuery)
            .all()
    }

    /// Get a specific \(name.lowercased()) by ID, scoped to current user
    func get\(name)(id: UUID) async throws -> \(name) {
\(scopeQuery)
            .where(\\.id == id)
            .first() else {
            throw AbortError(.notFound)
        }

        return \(name.lowercased())
    }

    /// Create a new \(name.lowercased()) scoped to current user
    func create\(name)(_ \(name.lowercased()): \(name)) async throws -> \(name) {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient
        let userScope = scope as! UserScope

        var created = \(name.lowercased())
        created.\(scope?.schemaKey ?? "id") = userScope.user!.id

        return try await repo.save(created)
    }

    /// Update a \(name.lowercased())
    func update\(name)(_ \(name.lowercased()): \(name)) async throws -> \(name) {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient

        var updated = \(name.lowercased())
        updated.updatedAt = Date()

        return try await repo.save(updated)
    }

    /// Delete a \(name.lowercased())
    func delete\(name)(_ \(name.lowercased()): \(name)) async throws {
        let repo = conn.assigns[SpectroKey.self] as! SpectroClient

        try await repo.delete(\(name.lowercased()))
    }
}
"""
    }
}
```

#### 2.5.2 Field Definition

```swift
// In Sources/RoostCLI/Generators/FieldDefinition.swift

public struct FieldDefinition: Sendable {
    public let name: String
    public let type: String
    public let isOptional: Bool
    public let isReference: Bool
    public let isArray: Bool

    public var swiftType: String {
        if isReference {
            return isOptional ? "UUID?" : "UUID"
        }

        if isOptional {
            return "\(baseSwiftType)?"
        }

        return baseSwiftType
    }

    public var postgresType: String {
        if isReference {
            return "UUID"
        }

        if isArray {
            return "\(basePostgresType)[]"
        }

        return basePostgresType
    }

    private var baseSwiftType: String {
        switch type.lowercased() {
        case "string": return "String"
        case "text": return "String"
        case "int", "integer": return "Int"
        case "double", "decimal", "float": return "Double"
        case "bool", "boolean": return "Bool"
        case "date", "datetime": return "Date"
        case "json": return "String"  // JSONB as String
        case "data", "binary": return "Data"
        case "uuid": return "UUID"
        default: return "String"
        }
    }

    private var basePostgresType: String {
        switch type.lowercased() {
        case "string": return "TEXT"
        case "text": return "TEXT"
        case "int", "integer": return "BIGINT"
        case "double", "decimal", "float": return "NUMERIC"
        case "bool", "boolean": return "BOOLEAN"
        case "date", "datetime": return "TIMESTAMPTZ"
        case "json": return "JSONB"
        case "data", "binary": return "BYTEA"
        case "uuid": return "UUID"
        default: return "TEXT"
        }
    }

    public init(name: String, type: String, optional: Bool = false, reference: Bool = false, array: Bool = false) {
        self.name = name
        self.type = type
        self.isOptional = optional
        self.isReference = reference
        self.isArray = array
    }
}
```

---

### 2.6 Generator Engine

#### 2.6.1 Generator API

```swift
// In Sources/RoostCLI/Generators/Generator.swift

public enum Generator {
    /// Generate a complete CRUD resource
    public static func resource(
        name: String,
        fields: [String],
        variant: GeneratorVariant = .html,
        scope: ScopeMetadata? = ScopeConfig.defaultMetadata(),
        outputDirectory: URL = "."
    ) throws -> [GeneratedFile]

    /// Generate a standalone model
    public static func model(
        name: String,
        fields: [String],
        outputDirectory: URL = "."
    ) throws -> [GeneratedFile]

    /// Generate a migration file
    public static func migration(
        name: String,
        change: Bool = false,
        outputDirectory: URL = "."
    ) throws -> GeneratedFile

    /// Generate a context for existing model
    public static func context(
        name: String,
        customMethods: [String] = [],
        scope: ScopeMetadata? = ScopeConfig.defaultMetadata(),
        outputDirectory: URL = "."
    ) throws -> GeneratedFile
}

public enum GeneratorVariant {
    case html
    case json
    case both
    case modelOnly
}

public struct GeneratedFile {
    public let path: URL
    public let content: String
    public let overwrite: Bool  // false = warn if exists

    public func write() throws {
        if FileManager.default.fileExists(atPath: path.path) && !overwrite {
            print("⚠️  \(path.path) already exists - skipping")
            return
        }

        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try content.write(to: path, atomically: true, encoding: .utf8)
        print("  create  \(path.path)")
    }
}
```

#### 2.6.2 Field Parsing

```swift
// In Sources/RoostCLI/Generators/FieldParser.swift

public enum FieldParser {
    public static func parse(_ fieldStrings: [String]) throws -> [FieldDefinition] {
        try fieldStrings.map { try parseField($0) }
    }

    private static func parseField(_ string: String) throws -> FieldDefinition {
        let components = string.split(separator: ":").map { String($0) }

        guard components.count >= 2 else {
            throw GeneratorError.invalidFieldFormat(string)
        }

        let name = components[0]
        let type = components[1]
        let optional = type.hasSuffix("?")
        let actualType = optional ? String(type.dropLast()) : type
        let reference = actualType == "reference"
        let array = actualType.hasSuffix("[]")
        let baseType = array ? String(actualType.dropLast(2)) : actualType

        return FieldDefinition(
            name: name,
            type: baseType,
            optional: optional,
            reference: reference,
            array: array
        )
    }
}

public enum GeneratorError: Error {
    case invalidFieldFormat(String)
    case unknownFieldType(String)
}
```

---

## 3. Acceptance Criteria

### 3.1 Resource Generator
- [ ] `roost generate resource` creates complete CRUD resources
- [ ] `--json` flag generates JSON API resources
- [ ] `--both` flag generates both HTML and JSON variants
- [ ] `--model-only` flag generates only model and context
- [ ] Generates model with Spectro `@Schema` macro
- [ ] Generates context with Phoenix-style CRUD operations
- [ ] Generates HTML views (index, show, new, edit) for HTML variant
- [ ] Generates JSON API routes for JSON variant
- [ ] Generates migration file
- [ ] All generated code is scoped to current user
- [ ] Generated code compiles without modifications
- [ ] Generator warns if files already exist

### 3.2 Model Generator
- [ ] `roost generate model` creates standalone models
- [ ] Supports field types: string, text, int, double, bool, date, json, data, uuid
- [ ] Supports optional fields with `?` suffix
- [ ] Supports foreign key references with `reference` type
- [ ] Supports array types with `[]` suffix
- [ ] Generates corresponding migration file
- [ ] Model uses correct Swift types for field types
- [ ] Migration uses correct Postgres types for field types

### 3.3 Migration Generator
- [ ] `roost generate migration` creates migration file
- [ ] Migration file has UP and DOWN sections
- [ ] Migration file is properly formatted
- [ ] `--change` flag generates change-based migration
- [ ] Migration uses current timestamp
- [ ] Migration description is human-readable

### 3.4 Context Generator
- [ ] `roost generate context` creates context for existing model
- [ ] `--methods` flag generates custom query methods
- [ ] Generated context follows Phoenix pattern
- [ ] Context methods are scoped to current user
- [ ] Context includes CRUD operations
- [ ] Context handles errors correctly

### 3.5 Template System
- [ ] Templates use Swift String interpolation
- [ ] Model template generates valid Spectro schemas
- [ ] Context template generates valid Swift code
- [ ] Route template generates valid Roost routes
- [ ] View template generates valid ESW templates
- [ ] Migration template generates valid SQL
- [ ] All templates are Sendable and thread-safe

### 3.6 Field Parsing
- [ ] Parses field type syntax correctly
- [ ] Handles optional fields with `?` suffix
- [ ] Handles reference fields with `reference` type
- [ ] Handles array fields with `[]` suffix
- [ ] Maps field types to Swift types correctly
- [ ] Maps field types to Postgres types correctly
- [ ] Throws clear error for invalid field format

### 3.7 Integration
- [ ] Integrates with scope system (spec 22)
- [ ] Integrates with migration system (spec 23)
- [ ] Uses Spectro ORM for model generation
- [ ] Uses ESW for view generation
- [ ] Generated routes work with existing router
- [ ] Generated contexts use injected database connection

### 3.8 CLI Experience
- [ ] All commands support `--help` flag
- [ ] Commands show generated file paths
- [ ] Commands warn if files already exist
- [ ] Commands report success/failure clearly
- [ ] Error messages are actionable
- [ ] Generators respect directory structure
- [ ] Generators create directories if needed

---

## 4. Non-goals

- No custom template system (built-in templates only)
- No template override mechanism
- No generator configuration files
- No interactive mode (always non-interactive)
- No test generation
- No factory/fixture generation
- No API versioning in generators
- No nested resource generation
- No GraphQL schema generation
- No OpenAPI/Swagger generation
- No database-specific optimizations
- No migration rollback generation
- No scaffold customization
- No hot-reloading of generated code

---

## 5. Dependencies

- **Spectro ORM** - For model generation with `@Schema` macro
- **ESW** - For HTML view template generation
- **Auth & Scope System (spec 22)** - For scoped resource generation
- **Database Migrations (spec 23)** - For migration file generation
- **Nexus Router** - For route generation

---

## 6. Usage Examples

```bash
# Typical workflow for a new resource
$ roost generate resource Post title:string body:text published:bool
$ roost db:migrate
# Add postsRoutes to App.swift
$ swift build

# Generate JSON API for mobile app
$ roost generate resource ApiKey --json name:string key:string scopes:json
$ roost db:migrate

# Add fields to existing model
$ roost generate migration AddSlugToPosts
# Edit migration to add slug column
$ roost db:migrate

# Generate context for legacy table
$ roost generate model LegacyUser name:string email:string
$ roost generate context LegacyUser
```

---

## 7. Future Enhancements

Possible follow-up features:

- **Template override system** - Custom templates in `.roost/templates/`
- **Generator configuration** - Customize defaults via config file
- **Test generation** - Generate Swift Testing test files
- **Factory generation** - Generate test data factories
- **Nested resources** - Generate nested CRUD with parent/child relationships
- **API versioning** - Generate versioned API endpoints
- **GraphQL schema** - Generate GraphQL types and resolvers
- **OpenAPI spec** - Generate OpenAPI/Swagger documentation
- **Interactive mode** - Prompt for field details instead of command-line args
- **Scaffold customization** - Choose which files to generate
- **Hot-reloading** - Auto-regenerate on file changes
