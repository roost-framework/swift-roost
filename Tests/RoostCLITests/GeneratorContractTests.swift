import Foundation
import Testing
@testable import RoostCLI

@Suite("Generator contracts")
struct GeneratorContractTests {
    @Test("App names cannot shadow framework modules", arguments: ["Roost", "RoostTest", "RoostCLI"])
    func frameworkModuleNames(name: String) async throws {
        let command = try New.parse([name, "--no-db", "--no-esw"])
        await #expect(throws: (any Error).self) {
            try await command.run()
        }
    }

    @Test("Existing files survive a conflicting batch without partial generation")
    func refuseOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "handwritten".write(to: root.appendingPathComponent("existing.swift"), atomically: true, encoding: .utf8)
        #expect(throws: FileCreator.Conflict.self) {
            try FileCreator.create([("new.swift", "new"), ("existing.swift", "replacement")], in: root.path)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("new.swift").path))
        #expect(try String(contentsOf: root.appendingPathComponent("existing.swift"), encoding: .utf8) == "handwritten")
    }

    @Test("Auth migrations sort by dependency, including a second generation in the same second")
    func migrationOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("Sources/Migrations")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let users = ProjectEditor.nextMigration(in: root.path, description: "create_users")
        let tokens = ProjectEditor.nextMigration(in: root.path, description: "create_user_tokens", offset: 1)
        try "".write(to: directory.appendingPathComponent(tokens), atomically: true, encoding: .utf8)
        let todos = ProjectEditor.nextMigration(in: root.path, description: "create_todos")
        #expect(users < tokens && tokens < todos)
        let epoch = try #require(Int64(users.split(separator: "_")[0]))
        #expect(epoch < Int64(Date().timeIntervalSince1970) + 60)
    }

    @Test("Route registration preserves handwritten app code and supports nested directories")
    func registration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = ProjectContext(root: root.path, appName: "Probe")
        try FileCreator.create([
            ("Package.swift", ProjectTemplates.packageSwift(appName: "Probe", includeDB: true, includeESW: true)),
            ("Sources/Probe/App.swift", ProjectTemplates.appSwift(appName: "Probe", includeDB: true) + "\n// handwritten\n"),
        ], in: root.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, contents) = try ProjectEditor.registeredApp(in: context, routes: ["todosRoutes()"], plugs: ["fetchCurrentUser(),"])
        #expect(contents.contains("// handwritten"))
        #expect(contents.contains("todosRoutes()"))
        #expect(contents.contains("fetchCurrentUser(),"))
        #expect(ProjectDiscovery.findRoot(from: root.appendingPathComponent("Sources/Probe").path) == root.path)
    }

    @Test("Reject identifiers that produce invalid Swift or reserved generated fields")
    func identifiers() throws {
        #expect(throws: FieldParserError.self) { try FieldParser.validateTypeName("../Bad") }
        #expect(throws: FieldParserError.self) { try FieldParser.parse(["id:uuid"]) }
        #expect(throws: FieldParserError.self) { try FieldParser.parse(["title:string", "title:text"]) }
        #expect(throws: FieldParserError.self) { try FieldParser.parse(["class:string"]) }
    }
}
