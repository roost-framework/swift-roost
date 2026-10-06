# Spec: Background Jobs

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), optionally Spectro (for Postgres backend)

---

## 1. Goal

Some work doesn't belong in a request cycle: sending emails, processing
uploads, generating reports, calling external APIs. Phoenix has Oban,
Rails has Sidekiq/GoodJob. Roost needs a job system that:

1. Runs jobs asynchronously outside the request/response cycle.
2. Persists jobs so they survive server restarts (Postgres-backed).
3. Retries failed jobs with exponential backoff.
4. Has a simple, type-safe API.

```swift
// Enqueue a job from a route handler:
try await Jobs.enqueue(SendWelcomeEmailJob(userId: user.id))

// Job definition:
struct SendWelcomeEmailJob: RoostJob {
    let userId: UUID

    func perform() async throws {
        let user = try await repo.get(User.self, id: userId)
        try await Mailer.deliver(WelcomeEmail(user: user))
    }
}
```

No Redis dependency. Postgres is the queue (same as GoodJob for Rails).

---

## 2. Scope

### 2.1 RoostJob Protocol

```swift
public protocol RoostJob: Codable, Sendable {
    /// The job's unique type identifier (defaults to the type name).
    static var jobName: String { get }

    /// Maximum retry attempts (default: 3).
    static var maxRetries: Int { get }

    /// Queue name (default: "default").
    static var queue: String { get }

    /// Execute the job.
    func perform() async throws
}

extension RoostJob {
    public static var jobName: String { String(describing: Self.self) }
    public static var maxRetries: Int { 3 }
    public static var queue: String { "default" }
}
```

### 2.2 Job Queue API

```swift
public enum Jobs {
    /// Enqueue a job for immediate processing.
    public static func enqueue<J: RoostJob>(_ job: J) async throws

    /// Enqueue a job to run after a delay.
    public static func enqueue<J: RoostJob>(
        _ job: J,
        runAt: Date
    ) async throws

    /// Enqueue a job to run on a specific queue.
    public static func enqueue<J: RoostJob>(
        _ job: J,
        on queue: String
    ) async throws
}
```

### 2.3 Job Storage

**Postgres-backed (production):**

```sql
CREATE TABLE roost_jobs (
    id          BIGSERIAL PRIMARY KEY,
    job_name    TEXT NOT NULL,
    queue       TEXT NOT NULL DEFAULT 'default',
    payload     JSONB NOT NULL,
    status      TEXT NOT NULL DEFAULT 'pending',
    attempts    INT NOT NULL DEFAULT 0,
    max_retries INT NOT NULL DEFAULT 3,
    run_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    failed_at   TIMESTAMPTZ,
    error       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jobs_fetch
    ON roost_jobs (queue, status, run_at)
    WHERE status = 'pending';
```

Table auto-created on first use.

**In-memory (dev/test):**

An actor-based queue for development and testing. Jobs are lost on
server restart — acceptable for dev. Useful for testing job logic
without a database.

### 2.4 Job Worker

A background process that polls for jobs and executes them:

```swift
public actor JobWorker {
    let queues: [String]       // Which queues to process
    let concurrency: Int       // Max concurrent jobs (default: 5)
    let pollInterval: Duration // How often to check for jobs (default: 1s)

    public func start() async { ... }
    public func stop() async { ... }
}
```

Worker lifecycle:
1. Poll the job store for pending jobs (`status = 'pending'` and
   `run_at <= now()`).
2. Lock the job (UPDATE SET status = 'running' with row locking).
3. Deserialize the payload and call `perform()`.
4. On success: delete the job (or mark as `completed`).
5. On failure: increment `attempts`, set `run_at` for retry with
   exponential backoff, or mark as `failed` if max retries exceeded.

### 2.5 Retry Strategy

Exponential backoff with jitter:

```
delay = base^attempt + random(0..jitter)
```

Default: `15s, 1m, 4m, 16m, 1h` (base 4, capped at 1 hour).

Failed jobs (exceeded max retries) are kept in the table with
`status = 'failed'` for inspection. A CLI command can retry or
delete them.

### 2.6 Integration with RoostApp

```swift
public protocol RoostApp {
    // Existing...
    var jobs: [any RoostJob.Type] { get }  // Register job types
}

extension RoostApp {
    public var jobs: [any RoostJob.Type] { [] }
}
```

The app registers job types so the worker knows how to deserialize them.
On boot, the job worker starts automatically if jobs are registered.

### 2.7 CLI Commands

```bash
$ roost jobs:work                  # Start a standalone worker
$ roost jobs:work --queue emails   # Process specific queue
$ roost jobs:status                # Show pending/running/failed counts
$ roost jobs:retry-failed          # Retry all failed jobs
$ roost jobs:clear-failed          # Delete all failed jobs
```

### 2.8 Testing Support

```swift
// In tests:
let testStore = InMemoryJobStore()
Jobs.configure(store: testStore)

try await Jobs.enqueue(SendWelcomeEmailJob(userId: user.id))
#expect(testStore.pending.count == 1)

// Execute pending jobs synchronously:
try await testStore.drainAll()
#expect(testStore.pending.count == 0)
```

---

## 3. Acceptance Criteria

- [ ] `RoostJob` protocol with `perform`, `jobName`, `maxRetries`, `queue`
- [ ] `Jobs.enqueue` adds a job to the store
- [ ] `Jobs.enqueue(_:runAt:)` schedules delayed jobs
- [ ] `JobWorker` polls and executes pending jobs
- [ ] Postgres store with auto-created table
- [ ] In-memory store for dev/test
- [ ] Row-level locking prevents double-processing
- [ ] Failed jobs retry with exponential backoff
- [ ] Jobs exceeding max retries marked as `failed`
- [ ] Job payloads are Codable (JSON serialization)
- [ ] Multiple queues with configurable concurrency
- [ ] Worker starts automatically when jobs are registered in the app
- [ ] `roost jobs:work` CLI for standalone workers
- [ ] `roost jobs:status` shows queue state
- [ ] `roost jobs:retry-failed` retries failed jobs
- [ ] Test store with `drainAll()` for synchronous testing
- [ ] `swift test` passes

---

## 4. Non-goals

- No recurring/cron jobs (use OS cron + enqueue, or add later).
- No job priorities beyond queue separation.
- No Redis backend (Postgres is the queue).
- No distributed job locking across servers (Postgres FOR UPDATE handles it).
- No job dashboard UI (CLI commands for inspection).
- No job middleware / hooks (before/after perform).
- No unique job constraints (deduplicate at the application level).
