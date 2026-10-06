import HTTPTypes

extension Connection {

    /// Returns a halted connection with an HTTP redirect response.
    ///
    /// Defaults to 303 See Other, which is the correct status for
    /// POST→GET redirects (e.g. after form submission). Use 301 or 302
    /// for permanent or temporary GET→GET redirects.
    ///
    /// ```swift
    /// // After a successful form POST:
    /// return conn.putFlash(.info, "Created!")
    ///     .redirect(to: "/items")
    ///
    /// // Permanent redirect:
    /// return conn.redirect(to: "/new-path", status: .movedPermanently)
    /// ```
    ///
    /// - Parameters:
    ///   - path: The URL or path to redirect to.
    ///   - status: The HTTP redirect status. Defaults to `.seeOther` (303).
    /// - Returns: A halted connection with the redirect response.
    public func redirect(
        to path: String,
        status: HTTPResponse.Status = .seeOther
    ) -> Connection {
        var copy = self
        copy.response.status = status
        if let location = HTTPField.Name("Location") {
            copy.response.headerFields[location] = path
        }
        copy.responseBody = .empty
        copy.isHalted = true
        return copy
    }
}
