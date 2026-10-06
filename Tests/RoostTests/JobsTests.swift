import Foundation
import Nexus
import NexusRouter
import Testing

@testable import Roost
@testable import RoostTest

// MARK: - Fixture: Shared recorder

/// Thread-safe execution recorder used by test jobs.
private final class JobRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _executed: [String] = []
    var failNextN: Int = 0

    func record(_ value: String) {
        lock.withLock { _executed.append(value) }
    }

    func shouldFail() -> Bool {
        lock.withLock {
            guard failNextN > 0 else { return false }
            failNextN -= 1
            return true
        }
    }

    var executed: [String] {
        lock.withLock { _executed }
    }
}

// MARK: - Fixture: Jobs

private struct RecordingJob: RoostJob {
    struct Parameters: Codable, Sendable {
        let value: String
    }

    init() {}

    func execute(parameters: Parameters, context: JobContext) async throws {
        let recorder = context.userInfo["recorder"] as! JobRecorder
        recorder.record(parameters.value)
    }
}

private struct RetryableJob: RoostJob {
    struct Parameters: Codable, Sendable {
        let value: String
    }

    static var retryStrategy: RetryStrategy { .exponentialJitter(maxAttempts: 3) }

    init() {}

    func execute(parameters: Parameters, context: JobContext) async throws {
        let recorder = context.userInfo["recorder"] as! JobRecorder
        if recorder.shouldFail() {
            throw JobError.simulatedFailure
        }
        recorder.record(parameters.value)
    }
}

private enum JobError: Error {
    case simulatedFailure
}

// MARK: - Fixture: DailyReportJob (for scheduled tests)

private struct DailyReportJob: RoostJob {
    struct Parameters: Codable, Sendable {}

    init() {}

    func execute(parameters: Parameters, context: JobContext) async throws {
        let recorder = context.userInfo["recorder"] as! JobRecorder
        recorder.record("daily_report")
    }
}

// MARK: - Fixture: SimpleApp

private struct SimpleApp: RoostApp {
    var jobs: (any RoostJobQueue)? { JobQueue.inMemory() }

    var scheduledJobs: [ScheduledJobEntry] {
        [schedule(DailyReportJob.self, parameters: .init(), cron: "0 8 * * 1-5")]
    }

    @RouteBuilder var routes: [Route] {
        POST("/work") { conn in
            let value = (try? conn.decode(as: [String: String].self))?["value"] ?? "default"
            try await conn.jobs.push(RecordingJob.self, parameters: .init(value: value))
            return conn.text("queued")
        }
    }
}

// MARK: - Tests

@Suite("Jobs Integration", .serialized)
struct JobsTests {

    // MARK: Enqueue and Execute

    @Suite("Enqueue and Execute")
    struct EnqueueAndExecute {

        @Test("Job executes inline when runJobsInline is true")
        func jobExecutesInline() async throws {
            let recorder = JobRecorder()
            let app = try await TestApp(SimpleApp.self)
            app.jobs.userInfo["recorder"] = recorder

            try await app.jobs.push(RecordingJob.self, parameters: .init(value: "hello"))

            #expect(recorder.executed == ["hello"])
        }

        @Test("Job stays pending when runJobsInline is false")
        func jobStaysPending() async throws {
            let app = try await TestApp(SimpleApp.self, runJobsInline: false)

            try await app.jobs.push(RecordingJob.self, parameters: .init(value: "queued"))

            let pending = app.jobs.pending(RecordingJob.self)
            #expect(pending.count == 1)
            #expect(pending[0].parameters.value == "queued")
        }

        @Test("Job is not executed when runJobsInline is false")
        func jobNotExecutedWhenNotInline() async throws {
            let recorder = JobRecorder()
            let app = try await TestApp(SimpleApp.self, runJobsInline: false)
            app.jobs.userInfo["recorder"] = recorder

            try await app.jobs.push(RecordingJob.self, parameters: .init(value: "nope"))

            #expect(recorder.executed.isEmpty)
        }

        @Test("Route handler can push a job via conn.jobs")
        func routePushesJob() async throws {
            let recorder = JobRecorder()
            let app = try await TestApp(SimpleApp.self)
            app.jobs.userInfo["recorder"] = recorder

            let response = try await app.post("/work", json: ["value": "from_route"])

            #expect(response.status == .ok)
            #expect(recorder.executed == ["from_route"])
        }
    }

    // MARK: Retry

    @Suite("Retry")
    struct RetryTests {

        @Test("Failed job is retried up to maxAttempts and eventually succeeds")
        func failedJobRetried() async throws {
            let recorder = JobRecorder()
            recorder.failNextN = 2  // fail first 2 attempts, succeed on 3rd

            let app = try await TestApp(SimpleApp.self)
            app.jobs.userInfo["recorder"] = recorder

            try await app.jobs.push(RetryableJob.self, parameters: .init(value: "retried"))

            #expect(recorder.executed == ["retried"], "Job should succeed on 3rd attempt")
            #expect(app.jobs.failedAttempts(RetryableJob.self) == 2)
        }

        @Test("Job is discarded after all attempts exhausted")
        func jobDiscardedAfterMaxAttempts() async throws {
            let recorder = JobRecorder()
            recorder.failNextN = 99  // always fail

            let app = try await TestApp(SimpleApp.self)
            app.jobs.userInfo["recorder"] = recorder

            try await app.jobs.push(RetryableJob.self, parameters: .init(value: "doomed"))

            #expect(recorder.executed.isEmpty)
            #expect(app.jobs.discarded(RetryableJob.self).count == 1)
            #expect(app.jobs.failedAttempts(RetryableJob.self) == 3)
        }
    }

    // MARK: Scheduled Jobs

    @Suite("Scheduled Jobs")
    struct ScheduledJobTests {

        @Test("Scheduled job appears in the schedule list")
        func scheduledJobRegistered() async throws {
            let app = try await TestApp(SimpleApp.self)

            let entry = app.jobs.schedule.first { $0.isJob(DailyReportJob.self) }

            #expect(entry != nil)
            #expect(entry?.cron == "0 8 * * 1-5")
        }

        @Test("Manually triggering a scheduled job executes it")
        func manuallyTriggerScheduled() async throws {
            let recorder = JobRecorder()
            let app = try await TestApp(SimpleApp.self)
            app.jobs.userInfo["recorder"] = recorder

            try await app.jobs.triggerScheduled(DailyReportJob.self)

            #expect(recorder.executed == ["daily_report"])
        }
    }
}
