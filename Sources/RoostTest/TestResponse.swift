import Foundation
import HTTPTypes

/// A response from a ``TestApp`` request, with convenient assertion helpers.
public struct TestResponse: Sendable {

    /// HTTP status code.
    public let status: HTTPResponse.Status

    /// Response headers.
    public let headers: HTTPFields

    /// Raw body data.
    public let body: Data

    /// Body as a UTF-8 string.
    public var text: String {
        String(data: body, encoding: .utf8) ?? ""
    }

    /// Body parsed as a JSON dictionary.
    ///
    /// Returns an empty dictionary if the body isn't valid JSON.
    public var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }

    /// Decodes the body as the given `Decodable` type.
    public func decode<T: Decodable>(as type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: body)
    }

    /// Returns the value of a response header, or `nil` if not present.
    public func header(_ name: HTTPField.Name) -> String? {
        headers[name]
    }

    /// Convenience: header lookup by raw string name.
    public func header(_ name: String) -> String? {
        guard let fieldName = HTTPField.Name(name) else { return nil }
        return headers[fieldName]
    }

    /// All `Set-Cookie` values parsed as name → value pairs.
    ///
    /// Only extracts the cookie name and value; attributes (Path, HttpOnly, etc.)
    /// are ignored.
    public var cookies: [String: String] {
        var result: [String: String] = [:]
        for field in headers where field.name == .setCookie {
            let parts = field.value.split(separator: ";", maxSplits: 1)
            guard let nameValue = parts.first else { continue }
            let pair = nameValue.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            result[String(pair[0]).trimmingCharacters(in: .whitespaces)] =
                String(pair[1]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
