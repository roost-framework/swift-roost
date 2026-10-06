import Foundation
import HTTPTypes
import Roost

extension TestApp {
    /// Create an independent cookie jar. Use two browsers to test user isolation.
    public func browser() -> TestBrowser<App> { TestBrowser(app: self) }

    public func post(_ path: String, form: [String: String], headers: [String: String] = [:]) async throws -> TestResponse {
        var headers = headers
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        return try await request(method: .post, path: path, body: encodeForm(form), headers: headers)
    }
}

/// A cookie-preserving, in-process browser. Redirects are deliberately returned
/// so tests can assert them and follow them explicitly.
public actor TestBrowser<App: RoostApp> {
    private let app: TestApp<App>
    private var cookies: [String: String] = [:]

    init(app: TestApp<App>) { self.app = app }

    public func get(_ path: String, headers: [String: String] = [:]) async throws -> TestResponse {
        try await request(method: .get, path: path, headers: headers)
    }

    public func post(_ path: String, form: [String: String], headers: [String: String] = [:]) async throws -> TestResponse {
        var headers = headers
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        return try await request(method: .post, path: path, body: encodeForm(form), headers: headers)
    }

    public func request(method: HTTPRequest.Method, path: String, body: Data? = nil, headers: [String: String] = [:]) async throws -> TestResponse {
        var headers = headers
        headers["Cookie"] = cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        let response = try await app.request(method: method, path: path, body: body, headers: headers)
        for field in response.headers where field.name == .setCookie {
            let parts = field.value.split(separator: ";", omittingEmptySubsequences: false)
            guard let first = parts.first else { continue }
            let pair = first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = String(pair[0]).trimmingCharacters(in: .whitespaces)
            if parts.dropFirst().contains(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "max-age=0" }) {
                cookies.removeValue(forKey: name)
            } else {
                cookies[name] = String(pair[1])
            }
        }
        return response
    }
}

private func encodeForm(_ values: [String: String]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let body = values.sorted { $0.key < $1.key }.map {
        "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }.joined(separator: "&")
    return Data(body.utf8)
}
