import Foundation
import Testing

@testable import Roost

@Suite("Mailer")
struct MailerTests {

    @Test("TestDelivery collects sent emails")
    func testDeliveryCollectsEmails() async throws {
        let testDelivery = TestDelivery()
        let email = Email(
            to: "user@example.com",
            from: "app@example.com",
            subject: "Hello",
            body: "Welcome!"
        )

        try await testDelivery.deliver(email)

        let emails = await testDelivery.sentEmails
        #expect(emails.count == 1)
        #expect(emails[0].to == "user@example.com")
        #expect(emails[0].from == "app@example.com")
        #expect(emails[0].subject == "Hello")
        #expect(emails[0].body == "Welcome!")
        #expect(emails[0].isHTML == false)
    }

    @Test("TestDelivery collects HTML emails")
    func testDeliveryCollectsHTMLEmails() async throws {
        let testDelivery = TestDelivery()
        let email = Email(
            to: "user@example.com",
            from: "app@example.com",
            subject: "Receipt",
            body: "<h1>Thank you</h1>",
            isHTML: true
        )

        try await testDelivery.deliver(email)

        let emails = await testDelivery.sentEmails
        #expect(emails.count == 1)
        #expect(emails[0].isHTML == true)
    }

    @Test("TestDelivery collects multiple emails in order")
    func testDeliveryCollectsMultipleEmails() async throws {
        let testDelivery = TestDelivery()

        try await testDelivery.deliver(Email(
            to: "a@example.com", from: "app@test.com",
            subject: "First", body: "one"
        ))
        try await testDelivery.deliver(Email(
            to: "b@example.com", from: "app@test.com",
            subject: "Second", body: "two"
        ))

        let emails = await testDelivery.sentEmails
        #expect(emails.count == 2)
        #expect(emails.map(\.to) == ["a@example.com", "b@example.com"])
    }

    @Test("TestDelivery reset clears collected emails")
    func testDeliveryReset() async throws {
        let testDelivery = TestDelivery()

        try await testDelivery.deliver(Email(
            to: "user@example.com", from: "app@test.com",
            subject: "Test", body: "body"
        ))
        #expect(await testDelivery.sentEmails.count == 1)

        await testDelivery.reset()

        #expect(await testDelivery.sentEmails.isEmpty)
    }

    @Test("LoggerDelivery does not throw")
    func loggerDeliveryDoesNotThrow() async throws {
        let delivery = LoggerDelivery()
        let email = Email(
            to: "user@example.com",
            from: "app@example.com",
            subject: "Test",
            body: "Logged, not sent"
        )

        try await delivery.deliver(email)
        // No assertion — just verifying it doesn't throw
    }

    @Test("Mailer facade uses configured delivery")
    func mailerFacadeUsesConfiguredDelivery() async throws {
        let testDelivery = TestDelivery()
        let previousDelivery = Mailer.delivery
        Mailer.delivery = testDelivery
        defer { Mailer.delivery = previousDelivery }

        try await Mailer.deliver(Email(
            to: "recipient@test.com",
            from: "sender@test.com",
            subject: "Facade test",
            body: "via Mailer facade"
        ))

        let emails = await testDelivery.sentEmails
        #expect(emails.count == 1)
        #expect(emails[0].subject == "Facade test")
    }

    @Test("Email struct has correct defaults")
    func emailDefaults() {
        let email = Email(
            to: "user@example.com",
            from: "app@example.com",
            subject: "Subject",
            body: "Body"
        )

        #expect(email.isHTML == false)
    }
}
