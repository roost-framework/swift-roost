import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenAuth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Generate a complete authentication system (User, UserToken, AuthRoutes, requireAuth)"
    )

    func run() async throws {
        let context = try resolveProject()
        let source = "Sources/\(context.appName)"
        guard FileManager.default.fileExists(atPath: "\(context.root)/\(source)/Views/layout.esw") else {
            throw ValidationError("Browser auth requires an ESW app with Views/layout.esw.")
        }
        let users = ProjectEditor.nextMigration(in: context.root, description: "create_users")
        let tokens = ProjectEditor.nextMigration(in: context.root, description: "create_user_tokens", offset: 1)
        let app = try ProjectEditor.registeredApp(in: context, routes: ["scope(\"/auth\") { authRoutes() }"], plugs: ["fetchCurrentUser(),"])
        try FileCreator.create([
            ("\(source)/Models/User.swift", AuthTemplates.userModel()),
            ("\(source)/Models/UserToken.swift", AuthTemplates.userTokenModel()),
            ("\(source)/Routes/AuthRoutes.swift", AuthTemplates.authRoutes()),
            ("\(source)/Plugs/FetchCurrentUser.swift", AuthTemplates.requireAuthPlug()),
            ("\(source)/Contexts/AccountsContext.swift", AuthTemplates.authHelper()),
            ("Sources/Migrations/\(users)", AuthTemplates.createUserTableMigration()),
            ("Sources/Migrations/\(tokens)", AuthTemplates.createUserTokensTableMigration()),
            ("\(source)/Views/auth/login.esw", AuthTemplates.loginTemplate()),
            ("\(source)/Views/auth/register.esw", AuthTemplates.registerTemplate()),
            ("\(source)/Views/auth/LoginView.swift", AuthTemplates.view(name: "LoginView", template: "login.esw")),
            ("\(source)/Views/auth/RegisterView.swift", AuthTemplates.view(name: "RegisterView", template: "register.esw")),
        ], in: context.root)
        try app.1.write(toFile: app.0, atomically: true, encoding: .utf8)
        RoostUI.noora.success(.alert("Authentication generated and registered. Run 'roost migrate' then visit /auth/register."))
    }
}
