import ArgumentParser

struct ProjectContext {
    let root: String
    let appName: String
}

func resolveProject() throws -> ProjectContext {
    guard let root = ProjectDiscovery.findRoot() else {
        RoostUI.noora.error(.alert(
            "No Package.swift found.",
            takeaways: ["Run this command from your project root."]
        ))
        throw ExitCode.failure
    }

    guard let appName = ProjectDiscovery.findAppName(in: root) else {
        RoostUI.noora.error(.alert(
            "Could not determine app name from Package.swift.",
            takeaways: ["Ensure you have an executableTarget or Sources/<AppName>/App.swift."]
        ))
        throw ExitCode.failure
    }

    return ProjectContext(root: root, appName: appName)
}
