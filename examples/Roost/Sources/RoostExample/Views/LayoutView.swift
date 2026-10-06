import Roost

@ESWTemplate("layout.esw")
struct LayoutView {
    let conn: Connection
    let title: String
    let content: String
}
