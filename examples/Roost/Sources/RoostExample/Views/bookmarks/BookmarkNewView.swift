import Roost

@ESWTemplate("new.esw")
struct BookmarkNewView {
    var values: [String: String] = [:]
    var errors = ValidationErrors()
}
