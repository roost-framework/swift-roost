import ArgumentParser
import Foundation

struct Server: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "server",
        abstract: "Start the development server with auto-rebuild (alias for build --watch)"
    )

    @Option(name: .long, help: "Port to run on")
    var port: Int?

    func run() async throws {
        var build = Build()
        build.watch = true
        build.port = port
        try await build.run()
    }
}
