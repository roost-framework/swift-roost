import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenHTML: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "html",
        abstract: "Generate a model, migration, routes, and ESW templates"
    )

    @Argument(help: "Model name (e.g. Donut)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. name:string price:double)")
    var fields: [String] = []

    func run() async throws {
        var resource = GenResource()
        resource.name = name
        resource.fields = fields
        resource.json = false
        try await resource.run()
    }
}
