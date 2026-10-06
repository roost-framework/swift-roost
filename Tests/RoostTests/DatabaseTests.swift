import Testing
@testable import Roost

@Suite("Database")
struct DatabaseTests {
    @Test func postgresWithExplicitValues() {
        let db = Database(
            hostname: "db.example.com",
            port: 5433,
            username: "admin",
            password: "secret",
            database: "myapp"
        )
        #expect(db.hostname == "db.example.com")
        #expect(db.port == 5433)
        #expect(db.username == "admin")
        #expect(db.password == "secret")
        #expect(db.database == "myapp")
    }

    @Test func postgresFactoryAppendsSuffix() {
        // In dev environment (default), database name gets _dev suffix
        let db = Database.postgres(database: "donut_shop")
        // Since tests run with Roost.env == .dev by default
        #expect(db.database == "donut_shop_dev")
    }

    @Test func postgresFactoryDefaultHostname() {
        let db = Database.postgres(database: "myapp")
        #expect(db.hostname == "localhost")
        #expect(db.port == 5432)
        #expect(db.username == "postgres")
        #expect(db.password == "postgres")
    }

    @Test func isSendable() {
        let db: any Sendable = Database.postgres(database: "test")
        #expect(db is Database)
    }
}
