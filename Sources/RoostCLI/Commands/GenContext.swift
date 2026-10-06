import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenContext: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Generate a Phoenix-style context for an existing model"
    )

    @Argument(help: "Model name in PascalCase (e.g. Post)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. title:string body:text)")
    var fields: [String] = []

    @Option(name: .long, help: "Scope foreign key column (e.g. user_id)")
    var scope: String?

    func run() async throws {
        let context = try resolveProject()
        try FieldParser.validateTypeName(name)
        let parsedFields = try FieldParser.parse(fields)
        let pluralName = pluralize(name)

        try FileCreator.create(
            at: "Sources/\(context.appName)/Contexts/\(pluralName)Context.swift",
            in: context.root,
            content: GeneratorTemplates.contextTemplate(
                name: name,
                pluralName: pluralName,
                fields: parsedFields,
                scopeKey: scope
            )
        )
    }
}
