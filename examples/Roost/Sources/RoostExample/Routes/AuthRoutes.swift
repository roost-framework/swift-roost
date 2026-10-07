import Roost

/// Registration and login, mounted under `/auth` in App.swift.
@RouteBuilder
func authRoutes() -> [Route] {
    GET("/register", RegistrationController.self, .new)
    POST("/register", RegistrationController.self, .create)
    GET("/login", SessionController.self, .new)
    POST("/login", SessionController.self, .create)
    DELETE("/logout", SessionController.self, .delete)
}
