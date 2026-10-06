import Roost

@ESWTemplate("login.esw")
struct LoginView {
    var email: String = ""
    var error: String? = nil
}
