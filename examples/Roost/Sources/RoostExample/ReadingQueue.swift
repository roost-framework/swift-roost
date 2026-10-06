import Roost

enum ReadingFilter: String, CaseIterable, Sendable {
    case unread, finished, all

    var label: String {
        switch self {
        case .unread: "To read"
        case .finished: "Finished"
        case .all: "All links"
        }
    }

    func includes(_ bookmark: Bookmark) -> Bool {
        switch self {
        case .unread: !bookmark.read
        case .finished: bookmark.read
        case .all: true
        }
    }
}

extension Bookmark {
    var domain: String {
        let host = URLComponents(string: url)?.host ?? url
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
