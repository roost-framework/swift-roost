import Roost
import Testing
@testable import RoostExample

@Test("Form input is trimmed, notes are optional, and an unchecked box becomes false")
func bookmarkValidForm() async throws {
    let input = try await FormValues([
        "title": "  Swift guide  ", "url": " https://swift.org/documentation/ ", "note": "",
    ]).decode(as: CreateBookmarkInput.self).validated()
    #expect(input.title == "Swift guide")
    #expect(input.url == "https://swift.org/documentation/")
    #expect(input.note.isEmpty)
    #expect(!input.read)
}

@Test("A saved link must be a complete web URL", arguments: [
    "javascript:alert(1)", "file:///tmp/notes", "https://", "not-a-link",
    "https://user:password@example.com/", "https://exa mple.com/",
])
func rejectsInvalidURLs(url: String) async throws {
    do {
        _ = try await CreateBookmarkInput(title: "Example", url: url, note: "", read: false).validated()
        Issue.record("Accepted an invalid URL")
    } catch let errors as ValidationErrors {
        #expect(!errors["url"].isEmpty)
    }
}

@Test("Whitespace-only titles cannot be saved")
func rejectsEmptyTitle() async throws {
    do {
        _ = try await CreateBookmarkInput(title: "  ", url: "https://swift.org", note: "", read: false).validated()
        Issue.record("Accepted an empty title")
    } catch let errors as ValidationErrors {
        #expect(!errors["title"].isEmpty)
    }
}
