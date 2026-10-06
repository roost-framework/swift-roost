import ArgumentParser

@main
struct RoostCLI: AsyncParsableCommand {
    static let version = "2.0.0"

    static let configuration = CommandConfiguration(
        commandName: "roost",
        abstract: "The Roost web framework CLI",
        version: version,
        subcommands: [
            New.self,
            Gen.self,
            Migrate.self,
            Server.self,
            Build.self,
        ]
    )
}
