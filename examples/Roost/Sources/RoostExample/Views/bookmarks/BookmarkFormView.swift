import Roost

@ESWTemplate("form.esw")
struct BookmarkFormView {
    let action: String
    let method: String
    let values: [String: String]
    let errors: ValidationErrors
    let button: String
}
