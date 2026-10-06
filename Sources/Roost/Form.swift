import ESW
import Foundation

/// Standard browser form: `<.form action="/items" method="post">...</.form>`.
/// Render through `conn.render(...)` to supply the request's CSRF context.
/// GET/external forms never receive a session token. PUT/PATCH/DELETE use POST
/// with `_method`. Content is already-rendered HTML; all attributes are escaped.
public struct Form: ESWComponent {
    public static func render(
        action: String,
        method: String = "post",
        id: String? = nil,
        `class`: String? = nil,
        multipart: Bool = false,
        attributes: [String: String] = [:],
        content: String = ""
    ) -> String {
        let context = FormRenderContext.current
        func fail(_ error: ViewRenderingError) -> String {
            context?.record(error)
            // There is no response boundary to throw to when render() is called
            // directly. Emit no form/controls; the marker makes misuse visible
            // in source. Inside conn.render the whole response is rejected.
            return "<!-- Roost form omitted: \(error.description) -->"
        }
        let method = method.lowercased()
        guard ["get", "post", "put", "patch", "delete"].contains(method) else {
            return fail(.invalidFormMethod)
        }
        guard !action.contains("\\"),
              !action.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let destination = URLComponents(string: action),
              destination.user == nil, destination.password == nil,
              destination.scheme == nil || ["http", "https"].contains(destination.scheme!.lowercased()),
              destination.scheme == nil || destination.host?.isEmpty == false,
              !action.hasPrefix("//") || destination.host?.isEmpty == false else {
            return fail(.invalidFormAction)
        }
        let reserved: Set<String> = ["action", "method", "id", "class", "enctype"]
        guard attributes.keys.allSatisfy({ key in
            !key.isEmpty && key.first?.isLetter == true && key.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-:").contains($0)
            } && !reserved.contains(key.lowercased())
        }) else { return fail(.invalidFormAttribute) }

        let localAction: Bool
        if destination.scheme == nil && destination.host == nil {
            localAction = true
        } else if let request = context?.connection.request,
                  let scheme = request.scheme, let authority = request.authority,
                  let origin = URLComponents(string: "\(scheme)://\(authority)") {
            let destinationScheme = destination.scheme?.lowercased() ?? scheme.lowercased()
            let destinationPort = destination.port ?? (destinationScheme == "https" ? 443 : 80)
            let originPort = origin.port ?? (scheme.lowercased() == "https" ? 443 : 80)
            localAction = destinationScheme == scheme.lowercased()
                && destination.host?.lowercased() == origin.host?.lowercased() && destinationPort == originPort
        } else {
            // An absolute destination requires a request origin to classify it.
            return fail(.missingCSRFContext)
        }

        var hidden = ""
        if method != "get" && localAction {
            guard let conn = context?.connection, !conn.csrfToken.isEmpty,
                  conn.csrfToken == conn.getSession("_csrf_token") else {
                return fail(.missingCSRFContext)
            }
            hidden += "<input type=\"hidden\" name=\"_csrf_token\" value=\"\(ESW.escape(conn.csrfToken))\">"
        }
        if method != "get" && method != "post" {
            hidden += "<input type=\"hidden\" name=\"_method\" value=\"\(method.uppercased())\">"
        }
        var attrs = " action=\"\(ESW.escape(action))\" method=\"\(method == "get" ? "get" : "post")\""
        if let id { attrs += " id=\"\(ESW.escape(id))\"" }
        if let `class` { attrs += " class=\"\(ESW.escape(`class`))\"" }
        if multipart { attrs += " enctype=\"multipart/form-data\"" }
        for (name, value) in attributes.sorted(by: { $0.key < $1.key }) {
            attrs += " \(name)=\"\(ESW.escape(value))\""
        }
        return "<form\(attrs)>\(hidden)\(content)</form>"
    }
}
