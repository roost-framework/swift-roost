import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenSchema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Generate a model and migration"
    )

    @Argument(help: "Model name (e.g. Donut)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. name:string price:double)")
    var fields: [String] = []

    func run() async throws {
        let context = try resolveProject()
        try FieldParser.validateTypeName(name)
        let parsedFields = try FieldParser.parse(fields)
        let tableName = pluralize(toSnakeCaseFromPascal(name))

        // Generate model
        try FileCreator.create(
            at: "Sources/\(context.appName)/Models/\(name).swift",
            in: context.root,
            content: GeneratorTemplates.model(
                name: name,
                tableName: tableName,
                fields: parsedFields
            )
        )

        // Generate migration
        let migrationFile = ProjectEditor.nextMigration(in: context.root, description: "create_\(tableName)")
        try FileCreator.create(
            at: "Sources/Migrations/\(migrationFile)",
            in: context.root,
            content: GeneratorTemplates.migration(
                tableName: tableName,
                fields: parsedFields
            )
        )
    }
}
