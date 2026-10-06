import Roost

@ESWTemplate("register.esw")
struct RegisterView {
    var email: String = ""
    var error: String? = nil
}
