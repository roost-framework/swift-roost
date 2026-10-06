import Roost

@ESWTemplate("edit.esw")
struct BookmarkEditView {
    let bookmark: Bookmark
    var values: [String: String]
    var errors: ValidationErrors

    init(bookmark: Bookmark, values: [String: String]? = nil, errors: ValidationErrors = ValidationErrors()) {
        self.bookmark = bookmark
        self.errors = errors
        self.values = values ?? ["title": bookmark.title, "url": bookmark.url,
                                 "note": bookmark.note, "read": String(bookmark.read)]
    }
}
