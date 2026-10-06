import ArgumentParser

struct Gen: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gen",
        abstract: "Code generators",
        subcommands: [
            GenResource.self,
            GenContext.self,
            GenMigration.self,
            GenSchema.self,
            GenJSON.self,
            GenHTML.self,
            GenAuth.self,
            GenDockerfile.self,
        ]
    )
}
