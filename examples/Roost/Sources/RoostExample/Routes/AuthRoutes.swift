import Roost

@RouteBuilder
func authRoutes() -> [Route] {
    GET("/register") { conn in
        try conn.render(RegisterView(), title: "Register")
    }
    POST("/register") { conn in
        let email = conn.bodyParams["email"] ?? ""
        do {
            let (user, token) = try await AccountsContext(repo: conn.repo()).register(
                email: email, password: conn.bodyParams["password"] ?? "")
            return conn.loginUser(user, token: token).0.putFlash(.info, "Account created").redirect(to: "/")
        } catch let errors as ValidationErrors {
            let message = errors.fieldErrors.sorted { $0.key < $1.key }.flatMap { $0.value }.joined(separator: ". ")
            return try conn.render(RegisterView(email: email, error: message), title: "Register", status: .unprocessableContent)
        }
    }
    GET("/login") { conn in
        try conn.render(LoginView(error: conn.flash.error), title: "Log in")
    }
    POST("/login") { conn in
        let email = conn.bodyParams["email"] ?? ""
        guard let (user, token) = try await AccountsContext(repo: conn.repo()).login(
            email: email, password: conn.bodyParams["password"] ?? "") else {
            return try conn.render(LoginView(email: email, error: "Invalid email or password"), title: "Log in", status: .unprocessableContent)
        }
        return conn.loginUser(user, token: token).0.putFlash(.info, "Logged in").redirect(to: "/")
    }
    DELETE("/logout") { conn in
        if let token = conn.authSessionToken {
            try await AccountsContext(repo: conn.repo()).revoke(token: token)
        }
        return conn.logoutUser().renewSessionID().deleteSession("_csrf_token").redirect(to: "/auth/login")
    }
}
