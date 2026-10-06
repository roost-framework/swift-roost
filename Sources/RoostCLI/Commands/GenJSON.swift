import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenJSON: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "json",
        abstract: "Generate a model, migration, and JSON API routes"
    )

    @Argument(help: "Model name (e.g. Donut)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. name:string price:double)")
    var fields: [String] = []

    func run() async throws {
        var resource = GenResource()
        resource.name = name
        resource.fields = fields
        resource.json = true
        try await resource.run()
    }
}
