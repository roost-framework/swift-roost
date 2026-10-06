# Spec: Flash Messages

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** Nexus sessionPlug (complete), ESW (complete)

---

## 1. Goal

After a form submission, the user gets redirected but has no feedback that
anything happened. Every web framework solves this with flash messages:
write-once, read-once, session-scoped storage that survives exactly one
redirect.

Phoenix has `put_flash(conn, :info, "Donut created!")` and `<%= @flash[:info] %>`
in templates. Rails has `flash[:notice]`. Roost needs the same.

```swift
// In a POST handler:
return conn
    .putFlash(.info, "Donut created!")
    .putRespHeader(.location, "/donuts")
    .respond(status: .seeOther)

// In a template:
<% if let msg = flash.info { %>
  <div class="flash info"><%= msg %></div>
<% } %>
```

---

## 2. Scope

### 2.1 Flash Plug

A plug that runs early in the pipeline (after `sessionPlug`) to:

1. **Read** flash data from the session into `conn.assigns` so templates can
   access it.
2. **Clear** the flash from the session after reading — ensuring messages
   display exactly once.
3. **Write** any new flash data set during the request back to the session
   via a `beforeSend` hook.

```swift
// Sources/Roost/Plugs/FlashPlug.swift
public func flashPlug() -> Plug
```

### 2.2 Connection Helpers

```swift
extension Connection {
    /// Stores a flash message to be displayed on the next request.
    ///
    /// - Parameters:
    ///   - level: The flash level (`.info`, `.error`, `.warning`).
    ///   - message: The message string.
    /// - Returns: The updated connection.
    public func putFlash(_ level: FlashLevel, _ message: String) -> Connection

    /// The current flash messages (read from the previous request's session).
    public var flash: Flash { get }
}

public enum FlashLevel: String, Sendable {
    case info
    case error
    case warning
}

public struct Flash: Sendable {
    public var info: String?
    public var error: String?
    public var warning: String?
}
```

### 2.3 Session Storage Format

Flash data is stored in the session under a single key (`_flash`) as a
JSON-encoded dictionary:

```json
{"info": "Donut created!"}
```

The plug reads this key, populates `conn.flash`, and deletes the key from the
session. New flash messages written via `putFlash` are serialized back to
`_flash` in the `beforeSend` hook.

### 2.4 Template Integration

Flash data is available in ESW templates as a regular assign. The layout
template can include a flash partial:

```html
<%! var flash: Flash %>
<% if let msg = flash.info { %>
  <div class="flash info"><%= msg %></div>
<% } %>
<% if let msg = flash.error { %>
  <div class="flash error"><%= msg %></div>
<% } %>
```

This requires `flash` to be passed through the layout's assigns. Roost's
default layout helper should inject it automatically.

---

## 3. Acceptance Criteria

- [ ] `putFlash(.info, "msg")` stores message for the next request
- [ ] Flash message is available in `conn.flash.info` on the subsequent request
- [ ] Flash message is cleared after being read (displays exactly once)
- [ ] Multiple flash levels can coexist (`.info` + `.error` in same redirect)
- [ ] `putFlash` called multiple times for the same level: last write wins
- [ ] Flash survives a 303 redirect (write in POST, read in GET)
- [ ] Flash is empty when no messages were set
- [ ] Flash works with cookie-based sessions (no server-side session store required)
- [ ] Flash plug is a no-op when no session plug is configured (no crash)
- [ ] Template can conditionally render flash messages
- [ ] `swift test` passes

---

## 4. Non-goals

- No flash styling or CSS — that's application-level.
- No JavaScript toast/dismissal behavior.
- No structured flash (objects, arrays). Messages are strings only.
- No flash persistence beyond one request (no "keep flash" mechanism).
- No flash for API/JSON responses — flash is an HTML-redirect pattern.
