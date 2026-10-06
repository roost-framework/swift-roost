import Foundation
import Roost
import Testing

@Suite("Form casting")
struct FormValuesTests {
    @Test("Forms preserve strings and cast checkbox, number, optional and array fields")
    func casting() throws {
        let form = FormValues(["title": "  <Swift> + &  ", "done": "on", "count": "12", "price": "12.5", "tags": "[\"a\",\"b\"]"])
        #expect(try form.decode("title", as: String.self) == "  <Swift> + &  ")
        #expect(try form.decode("done", as: Bool.self))
        #expect(try form.decode("unchecked", as: Bool.self) == false)
        #expect(try form.decode("count", as: Int.self) == 12)
        #expect(try form.decode("price", as: Double.self) == 12.5)
        #expect(try form.decode("missing", as: Int?.self) == nil)
        #expect(try form.decode("tags", as: [String].self) == ["a", "b"])
    }

    @Test("Invalid typed input has a field error and retains its original text")
    func invalidValue() throws {
        let form = FormValues(["count": "twelve"])
        do {
            _ = try form.decode("count", as: Int.self)
            Issue.record("Invalid integer was accepted")
        } catch let errors as ValidationErrors {
            #expect(errors["count"] == ["is invalid"])
            #expect(form.values["count"] == "twelve")
        }
    }
}
