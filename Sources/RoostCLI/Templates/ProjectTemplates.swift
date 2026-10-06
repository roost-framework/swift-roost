import Foundation

enum ProjectTemplates {
    static func appTests(appName: String) -> String {
        """
        import Testing
        import RoostTest
        @testable import \(appName)

        @Test("The app responds through its real middleware")
        func welcome() async throws {
            let app = try await TestApp(\(appName).self, database: .some(nil))
            let response = try await app.get("/")
            #expect(response.status.code == 200)
            #expect(response.text.contains("Welcome to \(appName)"))
        }
        """
    }

    // MARK: - Package.swift

    static func packageSwift(appName: String, includeDB: Bool, includeESW: Bool) -> String {
        var deps = """
                frameworkDependency,
        """

        var targetDeps = """
                    .product(name: "Roost", package: "swift-roost"),
        """

        let testDeps = """
                    .product(name: "RoostTest", package: "swift-roost"),
        """

        // ESW plugin requires a direct dependency — SPM does not allow
        // referencing build-tool plugins from transitive dependencies.
        var eswPlugins = ""
        if includeESW {
            targetDeps += """

                    .product(name: "ESW", package: "esw"),
            """
            deps += """

                    eswDependency,
            """
            eswPlugins = """
                        plugins: [
                            .plugin(name: "ESWBuildPlugin", package: "esw"),
                        ]
            """
        }

        let pluginsBlock = eswPlugins.isEmpty ? "" : ",\n\(eswPlugins)"

        return """
        // swift-tools-version: 6.3

        import PackageDescription
        import Foundation

        // Set this only when developing the framework repositories together.
        let ecosystem = ProcessInfo.processInfo.environment["ROOST_ECOSYSTEM_PATH"]
        let frameworkPath = ProcessInfo.processInfo.environment["ROOST_FRAMEWORK_PATH"]
            ?? ecosystem.map { "\\($0)/Roost" }
        let frameworkDependency: Package.Dependency = frameworkPath.map {
            .package(name: "swift-roost", path: $0)
        } ?? .package(url: "https://github.com/roost-framework/swift-roost", from: "\(RoostCLI.version)")
        let eswPath = ProcessInfo.processInfo.environment["ROOST_ESW_PATH"]
            ?? ecosystem.map { "\\($0)/esw" }
        let eswDependency: Package.Dependency = eswPath.map {
            .package(name: "esw", path: $0)
        } ?? .package(url: "https://github.com/roost-framework/ESW.git", from: "1.5.0")

        let package = Package(
            name: "\(appName)",
            platforms: [
                .macOS(.v14),
            ],
            dependencies: [
        \(deps)
            ],
            targets: [
                .executableTarget(
                    name: "\(appName)",
                    dependencies: [
        \(targetDeps)
                    ]\(pluginsBlock)
                ),
                .testTarget(
                    name: "\(appName)Tests",
                    dependencies: [
                        "\(appName)",
        \(testDeps)
                    ]
                ),
            ]
        )
        """
    }

    // MARK: - App.swift

    static func appSwift(appName: String, includeDB: Bool, includeESW: Bool = true) -> String {
        let dbName = appName
            .replacing(#/([a-z])([A-Z])/#) { "\($0.output.1)_\($0.output.2)" }
            .lowercased()

        let dbLine = includeDB
            ? "\n    let database: Database? = Database.postgres(database: \"\(dbName)\")\n"
            : ""
        let layout = includeESW ? """

            var layout: HTMLLayout? {
                { conn, title, content in LayoutView(conn: conn, title: title, content: content).render() }
            }

        """ : ""

        return """
        import Roost

        @main
        struct \(appName): RoostApp {\(dbLine)
            let sessionStore: (any SessionStore)? = MemorySessionStore()
        \(layout)

            var plugs: [Plug] {
                [requestId(), requestLogger(), roost_staticFiles()] + \(includeESW ? "browserPlugs()" : "[bodyParser()]") + [
                    // roost:plugs
                ]
            }

            @RouteBuilder var routes: [Route] {
                // roost:routes
                GET("/") { conn in
                    return try conn.json(value: ["message": "Welcome to \(appName)"])
                }
            }
        }
        """
    }

    // MARK: - CSS Mode

    enum CSSMode {
        case none
        case pico
        case tailwind
    }

    // MARK: - layout.esw

    static let layoutView = """
    import Roost

    @ESWTemplate("layout.esw")
    struct LayoutView {
        let conn: Connection
        let title: String
        let content: String
    }
    """

    static func layoutESW(appName: String, cssMode: CSSMode = .none) -> String {
        let picoLink = """
                <link rel="stylesheet" href="/css/pico.min.css">

        """
        let appCSSLink = """
                <link rel="stylesheet" href="/css/app.css">

        """

        let cssLinks: String
        switch cssMode {
        case .none:
            cssLinks = ""
        case .pico:
            cssLinks = picoLink + appCSSLink
        case .tailwind:
            cssLinks = appCSSLink
        }

        let themeAttr = cssMode == .pico ? #" data-theme="light""# : ""

        return """
        <!DOCTYPE html>
        <html lang="en"\(themeAttr)>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title><%= title %> — \(appName)</title>
            \(cssLinks.isEmpty ? "" : cssLinks.trimmingCharacters(in: .newlines))
        </head>
        <body>
            \(cssMode == .pico ? #"<main class="container">"# : "")
            <% if let message = conn.flash.info { %>
            <p role="status"><%= message %></p>
            <% } %>
            <% if let message = conn.flash.error { %>
            <p role="alert"><%= message %></p>
            <% } %>
            <%== content %>
            \(cssMode == .pico ? "</main>" : "")
        </body>
        </html>
        """
    }

    // MARK: - Tailwind config

    static func tailwindConfig(appName: String) -> String {
        """
        /** @type {import('tailwindcss').Config} */
        module.exports = {
          content: ["./Sources/\(appName)/Views/**/*.{esw,heex}"],
          theme: {
            extend: {},
          },
          plugins: [],
        }
        """
    }

    // MARK: - Tailwind input CSS

    static let tailwindInputCSS = """
    @tailwind base;
    @tailwind components;
    @tailwind utilities;
    """

    // MARK: - .gitignore

    static let gitignore = """
    .DS_Store
    .build/
    .swiftpm/
    Package.resolved
    *.xcodeproj
    xcuserdata/
    DerivedData/
    """

    // MARK: - .swift-format

    static let swiftFormat = """
    {
      "version": 1,
      "lineLength": 120,
      "indentation": {
        "spaces": 4
      },
      "respectsExistingLineBreaks": true,
      "lineBreakBeforeControlFlowKeywords": false,
      "lineBreakBeforeEachArgument": true,
      "lineBreakBeforeEachGenericRequirement": false,
      "prioritizeKeepingFunctionOutputTogether": true,
      "indentConditionalCompilationBlocks": true,
      "indentSwitchCaseLabels": false,
      "fileScopedDeclarationPrivacy": {
        "accessLevel": "private"
      },
      "multiElementCollectionTrailingCommas": true
    }
    """
}
