import Roost

@ESWTemplate("index.esw")
struct BookmarksIndexView {
    let bookmarks: [Bookmark]
    var filter: ReadingFilter = .unread

    var visible: [Bookmark] { bookmarks.filter { filter.includes($0) } }
}
