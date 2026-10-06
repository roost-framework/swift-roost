# Spec: Mailer

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), ESW templates (spec 01)

---

## 1. Goal

Every web app sends emails: confirmation links, password resets,
notifications. Phoenix has Swoosh, Rails has ActionMailer. Roost
needs a mailer that:

1. Uses ESW templates for email bodies (same engine as web views).
2. Supports multiple delivery backends (SMTP, API-based services).
3. Works with `RoostToken` for signed confirmation/reset links.
4. Has a dev mode that logs emails instead of sending them.

```swift
try await Mailer.deliver(
    WelcomeEmail(user: user),
    via: .smtp
)
```

---

## 2. Scope

### 2.1 Email Struct

```swift
public struct Email: Sendable {
    public var to: [String]
    public var from: String
    public var subject: String
    public var textBody: String?
    public var htmlBody: String?
    public var cc: [String]
    public var bcc: [String]
    public var replyTo: String?
    public var headers: [String: String]
}
```

### 2.2 RoostEmail Protocol

Define emails as types:

```swift
public protocol RoostEmail: Sendable {
    /// Build the email with recipients, subject, and body.
    func build() async throws -> Email
}
```

Example:

```swift
struct WelcomeEmail: RoostEmail {
    let user: User

    func build() async throws -> Email {
        let token = RoostToken.sign(
            user.id.uuidString,
            secret: Roost.secret
        )
        return Email(
            to: [user.email],
            from: "hello@myapp.com",
            subject: "Welcome to MyApp!",
            htmlBody: try ESW.render("emails/welcome", [
                "name": user.name,
                "confirmURL": "https://myapp.com/confirm?token=\(token)"
            ]),
            textBody: "Welcome, \(user.name)! Confirm: https://myapp.com/confirm?token=\(token)"
        )
    }
}
```

### 2.3 Delivery Backends

```swift
public protocol MailDelivery: Sendable {
    func deliver(_ email: Email) async throws
}
```

**Built-in backends:**

**Logger (dev default):**
```swift
public struct LoggerDelivery: MailDelivery {
    // Prints email to console instead of sending.
    // Shows to, from, subject, and body preview.
}
```

**SMTP:**
```swift
public struct SMTPDelivery: MailDelivery {
    public init(
        host: String,
        port: Int = 587,
        username: String,
        password: String,
        encryption: SMTPEncryption = .starttls
    )
}
```

SMTP implementation uses NIO for the TCP connection and implements the
SMTP protocol (EHLO, AUTH, MAIL FROM, RCPT TO, DATA). TLS via
`swift-nio-ssl`.

**Test (for assertions):**
```swift
public final class TestDelivery: MailDelivery, @unchecked Sendable {
    public var deliveredEmails: [Email] = []
    // Collects emails for test assertions.
}
```

### 2.4 Mailer Facade

```swift
public enum Mailer {
    /// Configure the default delivery backend.
    public static func configure(_ delivery: MailDelivery)

    /// Deliver an email using the configured backend.
    public static func deliver(_ email: RoostEmail) async throws

    /// Deliver using a specific backend (overrides default).
    public static func deliver(
        _ email: RoostEmail,
        via delivery: MailDelivery
    ) async throws
}
```

Environment-aware defaults:
- Dev: `LoggerDelivery` (prints to console).
- Test: `TestDelivery` (collects for assertions).
- Prod: Must be explicitly configured (fatal error if not set).

### 2.5 Configuration Convention

SMTP settings from environment variables:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=app@myapp.com
SMTP_PASSWORD=app-password
MAIL_FROM=hello@myapp.com
```

### 2.6 CLI Generator

```bash
$ roost gen.email WelcomeEmail
  create  Sources/MyApp/Emails/WelcomeEmail.swift
  create  Sources/MyApp/Views/emails/welcome.esw
  create  Sources/MyApp/Views/emails/welcome.text.esw
```

Generates:
- Email struct conforming to `RoostEmail`.
- HTML email template (ESW).
- Plain text email template (ESW).

---

## 3. Acceptance Criteria

- [ ] `Email` struct with to, from, subject, text/html body, cc, bcc
- [ ] `RoostEmail` protocol for type-safe email definitions
- [ ] `MailDelivery` protocol for delivery backends
- [ ] `LoggerDelivery` prints emails to console (dev default)
- [ ] `SMTPDelivery` sends emails via SMTP with STARTTLS
- [ ] `TestDelivery` collects emails for test assertions
- [ ] `Mailer.deliver` uses the configured default backend
- [ ] `Mailer.deliver(_:via:)` allows per-email backend override
- [ ] ESW templates work for email bodies
- [ ] Environment-aware defaults (logger in dev, test in test, explicit in prod)
- [ ] SMTP reads config from environment variables
- [ ] `roost gen.email` generates email struct + templates
- [ ] Emails support both HTML and plain text bodies
- [ ] `swift test` passes

---

## 4. Non-goals

- No API-based delivery (SendGrid, Resend, SES) — add as separate packages.
- No email attachment support (MIME multipart is complex, add later).
- No email queuing (use background jobs for async delivery).
- No email preview in browser (log output is sufficient for dev).
- No inline CSS processing for email HTML (use inline styles in templates).
- No bounce/delivery tracking.
