import Nexus
import Foundation

/// The standard browser middleware. Configure `RoostApp.sessionStore` as well.
/// JSON requests are protected too; use a separate pipeline for a bearer-only API.
public func browserPlugs() -> [Plug] {
    [bodyParser(.init(maxBodySize: 1_048_576)), methodOverride(), flashPlug(), roost_csrfProtection()]
}

extension Connection {
    public var csrfToken: String { assigns["csrfToken"] as? String ?? "" }

    /// Parse a UUID route identifier or return a client error before querying.
    public func requireParam(_ name: String) throws -> UUID {
        guard let id = params[name].flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.badRequest, message: "Invalid \(name)")
        }
        return id
    }
}
