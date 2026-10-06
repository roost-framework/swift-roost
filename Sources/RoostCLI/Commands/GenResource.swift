import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenResource: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resource",
        abstract: "Generate a complete CRUD resource (model, context, routes, views, migration)"
    )

    @Argument(help: "Model name in PascalCase (e.g. Post)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. title:string body:text published:bool)")
    var fields: [String] = []

    @Flag(name: .long, help: "Generate JSON API routes instead of HTML")
    var json = false

    @Flag(name: .long, help: "Generate both HTML and JSON API routes")
    var both = false

    @Flag(name: .long, help: "Generate only model, context, and migration (no routes/views)")
    var modelOnly = false

    @Option(name: .long, help: "Scope foreign key column (e.g. user_id)")
    var scope: String?

    func run() async throws {
        guard [json, both, modelOnly].filter({ $0 }).count <= 1 else {
            throw ValidationError("Choose one of --json, --both or --model-only.")
        }
        let context = try resolveProject()
        try FieldParser.validateTypeName(name)
        let parsedFields = try FieldParser.parse(fields)
        if let scope {
            guard scope == "user_id" || modelOnly else {
                throw ValidationError("Generated authenticated routes currently support --scope user_id. Use --model-only for a custom scope and provide its route authentication explicitly.")
            }
            guard !parsedFields.contains(where: { $0.columnName == scope }) else {
                throw ValidationError("The scope column is generated automatically; remove it from the field list.")
            }
        }
        let table = pluralize(toSnakeCaseFromPascal(name))
        let plural = pluralize(name)
        let source = "Sources/\(context.appName)"
        let migration = ProjectEditor.nextMigration(in: context.root, description: "create_\(table)")
        var files = [
            ("\(source)/Models/\(name).swift", GeneratorTemplates.model(name: name, tableName: table, fields: parsedFields, scopeKey: scope)),
            ("\(source)/Contexts/\(plural)Context.swift", GeneratorTemplates.contextTemplate(name: name, pluralName: plural, fields: parsedFields, scopeKey: scope)),
            ("Sources/Migrations/\(migration)", GeneratorTemplates.migration(tableName: table, fields: parsedFields, scopeKey: scope)),
            ("Tests/\(context.appName)Tests/\(name)InputTests.swift", GeneratorTemplates.inputTests(appName: context.appName, name: name, fields: parsedFields)),
        ]
        var registrations: [String] = []
        if !modelOnly {
            if !json {
                guard FileManager.default.fileExists(atPath: "\(context.root)/\(source)/Views/layout.esw") else {
                    throw ValidationError("HTML resources require ESW and Views/layout.esw. Use --json for an API-only app.")
                }
                files.append(("\(source)/Routes/\(plural)Routes.swift", GeneratorTemplates.htmlRoutes(name: name, pluralName: plural, fields: parsedFields, scopeKey: scope)))
                files += [
                    ("\(source)/Views/\(table)/index.esw", GeneratorTemplates.listTemplate(name: name, fields: parsedFields)),
                    ("\(source)/Views/\(table)/show.esw", GeneratorTemplates.showTemplate(name: name, fields: parsedFields)),
                    ("\(source)/Views/\(table)/new.esw", GeneratorTemplates.newTemplate(name: name, fields: parsedFields)),
                    ("\(source)/Views/\(table)/edit.esw", GeneratorTemplates.editTemplate(name: name, fields: parsedFields)),
                ]
                files += GeneratorTemplates.htmlViews(name: name, fields: parsedFields).map {
                    ("\(source)/Views/\(table)/\($0.0)", $0.1)
                }
                let call = "\(toLowerFirst(plural))Routes()"
                registrations.append(scope == nil ? call : "scope(\"/\", plugs: [requireAuth()]) { \(call) }")
            }
            if json || both {
                files.append(("\(source)/Routes/\(plural)ApiRoutes.swift", GeneratorTemplates.jsonApiRoutes(name: name, pluralName: plural, fields: parsedFields, scopeKey: scope)))
                registrations.append("\(toLowerFirst(plural))ApiRoutes()")
            }
        }
        let app = try ProjectEditor.registeredApp(in: context, routes: registrations)
        try FileCreator.create(files, in: context.root)
        if !registrations.isEmpty { try app.1.write(toFile: app.0, atomically: true, encoding: .utf8) }
        RoostUI.noora.success(.alert("Resource \(.primary(name)) generated and registered. Run 'roost migrate' then 'swift test'."))
    }
}
