import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenDockerfile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dockerfile",
        abstract: "Generate a multi-stage Dockerfile and .dockerignore for production deployment"
    )

    func run() async throws {
        let context = try resolveProject()

        let dockerfilePath = (context.root as NSString).appendingPathComponent("Dockerfile")
        let dockerignorePath = (context.root as NSString).appendingPathComponent(".dockerignore")

        // Check for existing files
        var skipped = false

        if FileManager.default.fileExists(atPath: dockerfilePath) {
            RoostUI.noora.warning(.alert("Dockerfile already exists — skipping."))
            skipped = true
        } else {
            try FileCreator.create(
                at: "Dockerfile",
                in: context.root,
                content: DockerfileTemplates.dockerfile(appName: context.appName)
            )
        }

        if FileManager.default.fileExists(atPath: dockerignorePath) {
            RoostUI.noora.warning(.alert(".dockerignore already exists — skipping."))
            skipped = true
        } else {
            try FileCreator.create(
                at: ".dockerignore",
                in: context.root,
                content: DockerfileTemplates.dockerignore()
            )
        }

        if !skipped {
            RoostUI.noora.success(.alert("Docker files generated!"))
        }

        RoostUI.noora.info(.alert(
            "Next steps:",
            takeaways: [
                "docker build -t \(context.appName) .",
                "docker run -p 8080:8080 \(context.appName)",
            ]
        ))
    }
}
