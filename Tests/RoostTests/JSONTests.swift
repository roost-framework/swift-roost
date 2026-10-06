import Foundation
import HTTPTypes
import Nexus
import Testing

@testable import Roost

@Suite("JSON")
struct JSONTests {

    private func makeConn() -> Connection {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "localhost",
            path: "/",
            headerFields: HTTPFields()
        )
        return Connection(request: request)
    }

    @Test func jsonPrettyEncodesValue() throws {
        let conn = makeConn()
        let result = try conn.jsonPretty(value: ["name": "donut"])

        #expect(result.response.status == .ok)
        #expect(result.isHalted)
        #expect(result.response.headerFields[.contentType] == "application/json")

        if case .buffered(let data) = result.responseBody {
            let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
            #expect(json["name"] == "donut")
        } else {
            Issue.record("Expected buffered body")
        }
    }

    @Test func jsonPrettyRespectsCustomStatus() throws {
        let conn = makeConn()
        let result = try conn.jsonPretty(status: .created, value: ["id": "1"])

        #expect(result.response.status == .created)
    }

    @Test func jsonPrettyInDevIsPrettyPrinted() throws {
        // Roost.env defaults to .dev in tests
        let conn = makeConn()
        let result = try conn.jsonPretty(value: ["a": "1", "b": "2"])

        if case .buffered(let data) = result.responseBody {
            let text = String(data: data, encoding: .utf8)!
            // Pretty-printed JSON has newlines and indentation
            #expect(text.contains("\n"))
            #expect(text.contains("  "))
        } else {
            Issue.record("Expected buffered body")
        }
    }
}
