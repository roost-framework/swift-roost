# Roost Specifications

This directory contains specifications and examples demonstrating Roost's architecture and patterns.

## Files

### ArchitectureComparison.md
Compares Roost with Hummingbird and Vapor, highlighting:
- Immutable vs mutable routing
- Declarative vs imperative route definition
- Testing strategies
- Rails/Phoenix inspiration

### RoutingPatterns.md
Documents Roost's routing patterns:
- Route functions as data
- Composable routes with `scope` and `forward`
- Controller-free handlers
- Frontend/API separation
- Phoenix-style pipelines

### DonutShopPatterns.swift
Code examples showing 10 key patterns:
1. Dual Frontend/API routes
2. Scope-based middleware
3. Route files as modules
4. Testing without server
5. Immutable configuration
6. Connection-based context
7. Repository pattern (no ORM)
8. Flash messages
9. CSRF protection
10. Static file serving

### DonutShopIntegrationSpec.swift
Integration test suite demonstrating:
- API route testing (JSON)
- Frontend route testing (HTML)
- CSRF protection behavior
- Flash message flow
- Static file serving
- Content negotiation
- Route composition

---

## Phoenix Feature Parity Specs

The following specs define the intended API for features under development.
Tests are written to the final API — they will compile once each feature ships.

### PubSubPatterns.swift
API design for `Roost.PubSub` (inspired by `Phoenix.PubSub`):
- In-memory adapter (dev/test, no external deps)
- Valkey adapter (production, distributed)
- `subscribe`, `broadcast`, `unsubscribe` interface
- Testing with the in-memory adapter

### PubSubIntegrationSpec.swift
Integration specs for PubSub:
- Subscribe and receive on matching topic
- Ignore messages on different topics
- Multiple subscribers all receive broadcasts
- Unsubscribe stops delivery
- HTTP route → PubSub broadcast integration
- Adapter selection by environment

### ChannelPatterns.swift
API design for `Roost.Channel` (inspired by `Phoenix.Channel`):
- `channel("/socket")` endpoint declaration
- `ChannelRouter` with topic pattern matching (`"room:*"`)
- `Channel` protocol: `join`, `handle`, `leave`
- `socket.broadcast` / `socket.broadcastFrom` / `socket.push`
- Event interception (server-side mutation before fan-out)
- Server-initiated push from background jobs
- Socket authentication via signed tokens
- Phoenix wire protocol framing (`phoenix.js` compatible)

### ChannelIntegrationSpec.swift
Integration specs for Channels:
- Join/leave lifecycle
- Authentication enforcement
- Presence list delivered on join
- Message broadcast to all subscribers
- `broadcastFrom` excludes sender
- Server push without a client event

### PresencePatterns.swift
API design for `Roost.Presence` (inspired by `Phoenix.Presence`):
- `Presence.track` / `Presence.untrack` / `Presence.list`
- Automatic `presence_diff` broadcasts on join/leave
- Multiple metas per key (multi-tab users)
- Phoenix-compatible diff format (`phoenix.js` Presence helpers work)
- Distributed mode (Phase 2): Valkey HSET + TTL heartbeat

### PresenceIntegrationSpec.swift
Integration specs for Presence:
- Tracked socket appears in `Presence.list`
- Join/leave diffs broadcast to all subscribers
- Multi-tab: two metas under one key
- User disappears only when all tabs leave

### JobsPatterns.swift
API design for `Roost.Jobs` (inspired by Elixir's Oban):
- `RoostJob` protocol with `Parameters: Codable`
- `RetryStrategy` per job type
- `conn.jobs.push(_:parameters:)` from route handlers
- Scheduled jobs (cron strings + convenience helpers)
- Job middleware (logging, metrics, tracing)
- Testing: inline execution, queue inspection, retry simulation
- Driver selection: `.inMemory()` / `.valkey(client:)` / `.postgres(spectro:)`

### JobsIntegrationSpec.swift
Integration specs for background jobs:
- HTTP action enqueues and executes job inline in tests
- Pending job inspection without execution
- Retry up to `maxAttempts`
- Discard after retries exhausted
- Scheduled job registration and manual trigger
- Job with database access

### SSEPatterns.swift
API design for `Roost.SSE` (Server-Sent Events):
- `conn.sse(stream:)` response helper
- `SSEBroadcaster<T>` fan-out actor (Roost service)
- `conn.sseStream(from:filter:eventType:id:)` — typed stream from broadcaster
- Per-client filtering
- Background job → broadcaster publish
- Client-side JavaScript example (native `EventSource`)

### SSEIntegrationSpec.swift
Integration specs for SSE:
- Correct `Content-Type: text/event-stream` header
- Unauthenticated request rejected
- Published events received by connected client
- Multiple clients receive same event (fan-out)
- Per-userID filtering
- Correct `event:` and `id:` SSE fields
- JSON-encoded `data:` field
- Job-triggered SSE publish

### PipelinePatterns.swift
API design for router pipelines (inspired by Phoenix router pipelines):
- `pipeline("browser") { ... }` — named plug stacks
- `scope("/", pipelines: ["browser", "authenticated"]) { ... }` — explicit attachment
- Layered pipelines (`:browser` + `:authenticated`)
- Anonymous inline pipelines for one-off middleware
- Pipeline as a reusable value
- Built-in pipeline plugs provided by Roost
- Dev server routing table with pipeline column

---

## Running the Specs

Existing specs use the DonutShop as the reference implementation:

```bash
cd ../DonutShop
swb                    # Build
swift test            # Run tests
```

The Phoenix feature parity specs (PubSub, Channels, Presence, Jobs, SSE, Pipeline)
reference `ChatApp` and `DashboardApp` which will be created as example apps
alongside their respective feature implementations.

## Key Takeaways

1. **Routes are data**: `[Route]` arrays, not mutated objects
2. **Composable**: Functions return routes, compose naturally
3. **Testable**: `TestApp` runs routes without server
4. **Rails-like**: File organization matches URLs
5. **Phoenix-like**: Pipelines for middleware composition
6. **Everything is a Service**: PubSub, Jobs, SSEBroadcaster all compose via swift-service-lifecycle
