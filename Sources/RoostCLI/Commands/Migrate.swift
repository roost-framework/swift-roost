import ArgumentParser
import Foundation

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Run database migrations",
        subcommands: [
            MigrateUp.self,
            MigrateDown.self,
            MigrateStatus.self,
        ],
        defaultSubcommand: MigrateUp.self
    )
}

private func runAppMigration(_ action: String) throws {
    let context = try resolveProject()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.currentDirectoryURL = URL(fileURLWithPath: context.root)
    process.arguments = ["swift", "run", context.appName, "migrate", action]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 { throw ExitCode.failure }
}

struct MigrateUp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "up", abstract: "Run pending migrations with the app's configuration")
    func run() async throws { try runAppMigration("up") }
}

struct MigrateDown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "down", abstract: "Rollback the last migration")
    func run() async throws { try runAppMigration("down") }
}

struct MigrateStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show migration status")
    func run() async throws { try runAppMigration("status") }
}
