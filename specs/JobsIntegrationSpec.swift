import Testing
import RoostTest
@testable import DonutShop

/// Integration specs for Roost.Jobs (background job queue).
///
/// Uses the in-memory driver with inline (synchronous) execution in tests —
/// no Valkey or Postgres worker process required.
@Suite("Jobs Integration Specs")
struct JobsIntegrationSpecs {

    // MARK: - Enqueue & Execute

    @Suite("Enqueue and Execute")
    struct EnqueueAndExecute {

        @Test("Registering a user enqueues and executes WelcomeEmailJob")
        func welcomeEmailSent() async throws {
            let app = try await TestApp(DonutShopApp.self)

            let response = try await app.post("/users", json: [
                "name":  "Alice",
                "email": "alice@example.com"
            ])

            #expect(response.status == .seeOther)
            // In-memory driver executes inline; email should already be "sent"
            let sentEmails = app.mailer.sentEmails
            #expect(sentEmails.count == 1)
            #expect(sentEmails[0].to == "alice@example.com")
            #expect(sentEmails[0].subject.contains("Welcome"))
        }

        @Test("Pending jobs can be inspected without executing")
        func inspectPendingJobs() async throws {
            let app = try await TestApp(DonutShopApp.self, runJobsInline: false)

            _ = try await app.post("/users", json: ["name": "Bob", "email": "bob@example.com"])

            let pending = app.jobs.pending(WelcomeEmailJob.self)
            #expect(pending.count == 1)
            #expect(pending[0].parameters.email == "bob@example.com")
        }

        @Test("Jobs are not executed when runJobsInline is false")
        func jobsNotExecutedWhenDisabled() async throws {
            let app = try await TestApp(DonutShopApp.self, runJobsInline: false)

            _ = try await app.post("/users", json: ["name": "Carol", "email": "carol@example.com"])

            #expect(app.mailer.sentEmails.isEmpty)
        }
    }

    // MARK: - Retry

    @Suite("Retry")
    struct RetryTests {

        @Test("Failed job is retried up to maxAttempts")
        func failedJobRetried() async throws {
            let app = try await TestApp(DonutShopApp.self)

            // Simulate mailer failure for this test
            app.mailer.failNextN = 2  // fail first 2 attempts

            _ = try await app.post("/users", json: ["name": "Dave", "email": "dave@example.com"])

            // In-memory driver retries inline; job should eventually succeed
            #expect(app.mailer.sentEmails.count == 1)
            #expect(app.jobs.failedAttempts(WelcomeEmailJob.self) == 2)
        }

        @Test("Job is discarded after maxAttempts exhausted")
        func jobDiscardedAfterMaxAttempts() async throws {
            let app = try await TestApp(DonutShopApp.self)
            app.mailer.alwaysFail = true

            _ = try await app.post("/users", json: ["name": "Eve", "email": "eve@example.com"])

            #expect(app.mailer.sentEmails.isEmpty)
            #expect(app.jobs.discarded(WelcomeEmailJob.self).count == 1)
        }
    }

    // MARK: - Scheduled jobs

    @Suite("Scheduled Jobs")
    struct ScheduledJobTests {

        @Test("Scheduled job appears in the schedule list")
        func scheduledJobRegistered() async throws {
            let app = try await TestApp(DonutShopApp.self)

            let schedule = app.jobs.schedule
            let reportJob = schedule.first { $0.jobType == DailyReportJob.self }

            #expect(reportJob != nil)
            #expect(reportJob?.cron == "0 8 * * 1-5")
        }

        @Test("Manually triggering a scheduled job executes it")
        func manuallyTriggerScheduled() async throws {
            let app = try await TestApp(DonutShopApp.self)

            try await app.jobs.triggerScheduled(DailyReportJob.self)

            #expect(app.reports.generated.count == 1)
        }
    }

    // MARK: - Job with database

    @Suite("Job with Database Access")
    struct JobWithDatabase {

        @Test("OrderConfirmationJob updates order status")
        func confirmationUpdatesStatus() async throws {
            let app   = try await TestApp(DonutShopApp.self)
            let order = Order(id: UUID(), userID: UUID(), userEmail: "frank@example.com", status: "pending")
            try await app.spectro.insert(order)

            try await app.jobs.push(OrderConfirmationJob.self, parameters: .init(orderID: order.id))

            let updated = try await app.spectro.find(Order.self, id: order.id)
            #expect(updated.status == "confirmed")
        }

        @Test("OrderConfirmationJob is a no-op for unknown order")
        func noOpForUnknownOrder() async throws {
            let app = try await TestApp(DonutShopApp.self)

            // Should not throw — discards gracefully
            try await app.jobs.push(OrderConfirmationJob.self, parameters: .init(orderID: UUID()))

            #expect(app.jobs.discarded(OrderConfirmationJob.self).isEmpty, "Graceful no-op, not a failure")
        }
    }
}
