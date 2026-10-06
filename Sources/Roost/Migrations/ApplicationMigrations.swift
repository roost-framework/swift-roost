import Foundation
import Spectro

extension RoostApp {
    /// Run migrations with exactly the same database configuration as the server.
    /// Available in a compiled release too: `MyApp migrate up|down|status`.
    package func runMigrationCommand(_ arguments: [String]) async throws {
        guard arguments.count == 1, ["up", "down", "status"].contains(arguments[0]) else {
            throw MigrationCommandError("Usage: \(Self.self) migrate up|down|status")
        }
        guard let config = database else { throw MigrationCommandError("No database configured in \(Self.self).") }
        let client = try SpectroClient(hostname: config.hostname, port: config.port,
            username: config.username, password: config.password, database: config.database)
        let migrator = RoostMigrator(database: client)
        do {
            switch arguments[0] {
            case "up":
                let pending = try await migrator.pending()
                print("Applying \(pending.count) migration(s) to \(config.database)")
                try await migrator.migrate()
            case "down": try await migrator.rollback()
            default: try await migrator.status().printReport()
            }
        } catch {
            await client.shutdown()
            throw error
        }
        await client.shutdown()
    }
}

private struct MigrationCommandError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
