import Foundation
import HTTPTypes
import Nexus

// MARK: - Dev Error Page

/// Renders a detailed, styled HTML error page for development.
///
/// Shows error type, message, request info, headers, assigns, and pipeline
/// trace. Dark theme, monospace, inline CSS — no external dependencies.
func devErrorPageHTML(
    status: Int,
    errorType: String,
    message: String,
    conn: Connection
) -> String {
    let method = conn.request.method.rawValue
    let path = conn.request.path ?? "/"

    let headersHTML = conn.request.headerFields.map { field in
        "<tr><td>\(escapeHTML(field.name.rawName))</td><td>\(escapeHTML(field.value))</td></tr>"
    }.joined(separator: "\n")

    let assignsHTML: String
    if conn.assigns.isEmpty {
        assignsHTML = "<p class=\"empty\">No assigns</p>"
    } else {
        let rows = conn.assigns.map { key, value in
            "<tr><td>\(escapeHTML(key))</td><td>\(escapeHTML(String(describing: value)))</td></tr>"
        }.joined(separator: "\n")
        assignsHTML = "<table>\(rows)</table>"
    }

    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>\(status) — \(escapeHTML(errorType))</title>
    <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: ui-monospace, 'SF Mono', Menlo, monospace;
        background: #1a1a2e;
        color: #e0e0e0;
        padding: 2rem;
        line-height: 1.6;
    }
    .container { max-width: 960px; margin: 0 auto; }
    .status {
        font-size: 4rem;
        font-weight: 700;
        color: #e94560;
        margin-bottom: 0.25rem;
    }
    .error-type {
        font-size: 1.25rem;
        color: #e94560;
        margin-bottom: 0.5rem;
    }
    .message {
        font-size: 1.1rem;
        color: #fff;
        background: #16213e;
        padding: 1rem;
        border-radius: 6px;
        margin-bottom: 2rem;
        border-left: 4px solid #e94560;
    }
    h2 {
        font-size: 0.85rem;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: #888;
        margin: 1.5rem 0 0.75rem;
        border-bottom: 1px solid #2a2a4a;
        padding-bottom: 0.5rem;
    }
    .request-line {
        font-size: 1rem;
        color: #0f3460;
        background: #e0e0e0;
        display: inline-block;
        padding: 0.25rem 0.75rem;
        border-radius: 4px;
        margin-bottom: 1rem;
    }
    .request-line .method {
        color: #e94560;
        font-weight: 700;
    }
    table {
        width: 100%;
        border-collapse: collapse;
        font-size: 0.85rem;
    }
    td {
        padding: 0.4rem 0.75rem;
        border-bottom: 1px solid #2a2a4a;
        vertical-align: top;
    }
    td:first-child {
        color: #53a8b6;
        white-space: nowrap;
        width: 30%;
    }
    .empty { color: #555; font-style: italic; font-size: 0.85rem; }
    .footer {
        margin-top: 3rem;
        font-size: 0.75rem;
        color: #555;
        border-top: 1px solid #2a2a4a;
        padding-top: 1rem;
    }
    </style>
    </head>
    <body>
    <div class="container">
        <div class="status">\(status)</div>
        <div class="error-type">\(escapeHTML(errorType))</div>
        <div class="message">\(escapeHTML(message))</div>

        <h2>Request</h2>
        <div class="request-line"><span class="method">\(method)</span> \(escapeHTML(path))</div>

        <h2>Request Headers</h2>
        <table>\(headersHTML)</table>

        <h2>Assigns</h2>
        \(assignsHTML)

        <div class="footer">Roost dev error page — this is only shown in development.</div>
    </div>
    </body>
    </html>
    """
}

// MARK: - Prod Error Page

/// Renders a minimal, clean HTML error page for production.
///
/// Shows only the status code and a generic message. No internals exposed.
func prodErrorPageHTML(status: Int, reason: String) -> String {
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>\(status)</title>
    <style>
    body {
        font-family: -apple-system, system-ui, sans-serif;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 100vh;
        margin: 0;
        background: #fafafa;
        color: #333;
    }
    .error {
        text-align: center;
    }
    .status {
        font-size: 4rem;
        font-weight: 700;
        color: #999;
    }
    .reason {
        font-size: 1.1rem;
        color: #666;
        margin-top: 0.5rem;
    }
    </style>
    </head>
    <body>
    <div class="error">
        <div class="status">\(status)</div>
        <div class="reason">\(escapeHTML(reason))</div>
    </div>
    </body>
    </html>
    """
}

// MARK: - Helpers

private func escapeHTML(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

/// Returns a generic reason phrase for common HTTP status codes.
func reasonPhrase(for status: Int) -> String {
    switch status {
    case 400: "Bad Request"
    case 401: "Unauthorized"
    case 403: "Forbidden"
    case 404: "Not Found"
    case 405: "Method Not Allowed"
    case 408: "Request Timeout"
    case 409: "Conflict"
    case 410: "Gone"
    case 413: "Payload Too Large"
    case 415: "Unsupported Media Type"
    case 422: "Unprocessable Entity"
    case 429: "Too Many Requests"
    case 500: "Internal Server Error"
    case 502: "Bad Gateway"
    case 503: "Service Unavailable"
    case 504: "Gateway Timeout"
    default: "Error"
    }
}
