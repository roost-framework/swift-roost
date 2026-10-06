import ArgumentParser

@main
struct RoostCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "roost",
        abstract: "The Roost web framework CLI",
        subcommands: [
            New.self,
            Gen.self,
            Migrate.self,
            Server.self,
            Build.self,
        ]
    )
}
