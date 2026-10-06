import ArgumentParser
import Foundation
@preconcurrency import Noora

struct New: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new Roost project"
    )

    @Argument(help: "Name of the project (e.g. DonutShop)")
    var appName: String

    @Flag(name: .long, help: "Omit database configuration")
    var noDb = false

    @Flag(name: .long, help: "Omit Views directory and ESW templates")
    var noEsw = false

    @Option(name: .long, help: "Pico CSS color theme (default: orange). Mutually exclusive with --tailwind.")
    var color: String?

    @Flag(name: .long, help: "Use Tailwind CSS instead of Pico CSS. Mutually exclusive with --color.")
    var tailwind = false

    static let validColors: [String] = [
        "amber", "blue", "cyan", "fuchsia", "green", "grey", "indigo", "jade",
        "lime", "orange", "pink", "pumpkin", "purple", "red", "sand", "slate",
        "violet", "yellow", "zinc",
    ]

    func run() async throws {
        try FieldParser.validateTypeName(appName)
        guard !["Roost", "RoostTest", "RoostCLI"].contains(appName) else {
            throw ValidationError("'\(appName)' is a framework module. Choose an app name such as RoostExample to avoid a Swift module collision.")
        }
        let cwd = FileManager.default.currentDirectoryPath
        let projectDir = (cwd as NSString).appendingPathComponent(appName)

        guard !FileManager.default.fileExists(atPath: projectDir) else {
            RoostUI.noora.error(.alert(
                "Directory \(.primary(appName)) already exists.",
                takeaways: ["Choose a different name or remove the existing directory."]
            ))
            throw ExitCode.failure
        }

        // Validate mutually exclusive flags
        if tailwind && color != nil {
            RoostUI.noora.error(.alert(
                "Options \(.primary("--tailwind")) and \(.primary("--color")) are mutually exclusive.",
                takeaways: ["Use --tailwind for Tailwind CSS, or --color <name> for Pico CSS."]
            ))
            throw ExitCode.failure
        }

        // Validate color value
        let resolvedColor = color ?? "orange"
        if color != nil && !Self.validColors.contains(resolvedColor) {
            RoostUI.noora.error(.alert(
                "Invalid color \(.primary(resolvedColor)).",
                takeaways: ["Available colors: \(Self.validColors.joined(separator: ", "))"]
            ))
            throw ExitCode.failure
        }

        RoostUI.noora.info(.alert("Creating \(.primary(appName))..."))

        let includeDB = !noDb
        let includeESW = !noEsw

        // Determine CSS mode
        let cssMode: ProjectTemplates.CSSMode
        if noEsw {
            cssMode = .none
        } else if tailwind {
            cssMode = .tailwind
        } else {
            cssMode = .pico
        }

        // Package.swift
        try FileCreator.create(
            at: "Package.swift",
            in: projectDir,
            content: ProjectTemplates.packageSwift(
                appName: appName,
                includeDB: includeDB,
                includeESW: includeESW
            )
        )

        // App.swift
        try FileCreator.create(
            at: "Sources/\(appName)/App.swift",
            in: projectDir,
            content: ProjectTemplates.appSwift(appName: appName, includeDB: includeDB, includeESW: includeESW)
        )

        // Routes/.gitkeep
        try FileCreator.create(
            at: "Sources/\(appName)/Routes/.gitkeep",
            in: projectDir,
            content: ""
        )

        // Models/.gitkeep
        try FileCreator.create(
            at: "Sources/\(appName)/Models/.gitkeep",
            in: projectDir,
            content: ""
        )

        // Views/layout.esw (if ESW enabled)
        if includeESW {
            try FileCreator.create(
                at: "Sources/\(appName)/Views/LayoutView.swift",
                in: projectDir,
                content: ProjectTemplates.layoutView
            )
            try FileCreator.create(
                at: "Sources/\(appName)/Views/layout.esw",
                in: projectDir,
                content: ProjectTemplates.layoutESW(appName: appName, cssMode: cssMode)
            )
        }

        // Migrations/.gitkeep (if DB enabled)
        if includeDB {
            try FileCreator.create(
                at: "Sources/Migrations/.gitkeep",
                in: projectDir,
                content: ""
            )
        }

        // Tests/.gitkeep
        try FileCreator.create(
            at: "Tests/\(appName)Tests/AppTests.swift",
            in: projectDir,
            content: ProjectTemplates.appTests(appName: appName)
        )

        // Public/ directory structure for static file serving
        try FileCreator.create(
            at: "Public/css/.gitkeep",
            in: projectDir,
            content: ""
        )
        try FileCreator.create(
            at: "Public/js/.gitkeep",
            in: projectDir,
            content: ""
        )
        try FileCreator.create(
            at: "Public/images/.gitkeep",
            in: projectDir,
            content: ""
        )

        // CSS setup (skip if --no-esw)
        if !noEsw {
            switch cssMode {
            case .pico:
                try await setupPicoCSS(in: projectDir, color: resolvedColor)
            case .tailwind:
                try await setupTailwindCSS(in: projectDir)
            case .none:
                break
            }
        }

        // .gitignore
        let gitignoreContent = tailwind
            ? ProjectTemplates.gitignore + "\n.build/tailwindcss\n"
            : ProjectTemplates.gitignore
        try FileCreator.create(
            at: ".gitignore",
            in: projectDir,
            content: gitignoreContent
        )

        // .swift-format
        try FileCreator.create(
            at: ".swift-format",
            in: projectDir,
            content: ProjectTemplates.swiftFormat
        )

        RoostUI.noora.success(.alert(
            "Project \(.primary(appName)) created",
            takeaways: [
                "cd \(.command(appName))",
                "swift run",
            ]
        ))
    }

    // MARK: - Pico CSS Setup

    private func setupPicoCSS(in projectDir: String, color: String) async throws {
        // Download Pico CSS
        let picoFileName = color == "orange" ? "pico.min.css" : "pico.\(color).min.css"
        let picoURL = URL(string: "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/\(picoFileName)")!
        let picoDestination = (projectDir as NSString).appendingPathComponent("Public/css/pico.min.css")

        RoostUI.noora.info(.alert("Downloading Pico CSS (\(.primary(color)))..."))

        do {
            try await Downloader.download(from: picoURL, to: picoDestination)
            RoostUI.noora.success(.alert("create  \(.muted("Public/css/pico.min.css"))"))
        } catch {
            RoostUI.noora.warning(.alert(
                "Could not download Pico CSS: \(error.localizedDescription)"
            ))
            RoostUI.noora.info(.alert(
                "You can manually download it from \(picoURL.absoluteString)"
            ))
        }

        // Create app.css
        try FileCreator.create(
            at: "Public/css/app.css",
            in: projectDir,
            content: "/* App-specific styles */\n"
        )
    }

    // MARK: - Tailwind CSS Setup

    private func setupTailwindCSS(in projectDir: String) async throws {
        // Download Tailwind binary
        let binaryName = Platform.tailwindBinaryName
        let tailwindURL = URL(
            string: "https://github.com/tailwindlabs/tailwindcss/releases/latest/download/\(binaryName)"
        )!
        let tailwindDestination = (projectDir as NSString).appendingPathComponent(".build/tailwindcss")

        RoostUI.noora.info(.alert("Downloading Tailwind CSS CLI..."))

        do {
            try await Downloader.download(from: tailwindURL, to: tailwindDestination)

            // Make binary executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tailwindDestination
            )
            RoostUI.noora.success(.alert("create  \(.muted(".build/tailwindcss"))"))
        } catch {
            RoostUI.noora.warning(.alert(
                "Could not download Tailwind CSS CLI: \(error.localizedDescription)"
            ))
            RoostUI.noora.info(.alert(
                "You can manually download it from \(tailwindURL.absoluteString)"
            ))
            RoostUI.noora.info(.alert(
                "Place the binary at .build/tailwindcss and make it executable."
            ))
        }

        // Create tailwind.config.js
        try FileCreator.create(
            at: "tailwind.config.js",
            in: projectDir,
            content: ProjectTemplates.tailwindConfig(appName: appName)
        )

        // Create input.css with Tailwind directives
        try FileCreator.create(
            at: "Public/css/input.css",
            in: projectDir,
            content: ProjectTemplates.tailwindInputCSS
        )
    }
}
