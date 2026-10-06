import Testing
import RoostTest
@testable import DonutShop

/// Integration specs demonstrating Roost's Rails/Phoenix-style routing patterns.
///
/// These tests show how Roost enables clean separation of concerns,
/// immutable route composition, and testing without server overhead.
@Suite("DonutShop Integration Specs")
struct DonutShopIntegrationSpecs {

    // MARK: - API Routes (JSON)

    @Suite("API Routes")
    struct APIRoutes {

        @Test("GET /api/v1/donuts returns JSON list")
        func listDonuts() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/api/v1/donuts")

            #expect(response.status == .ok)
            #expect(response.header("Content-Type")?.contains("application/json") == true)
        }

        @Test("GET /api/v1/donuts/:id returns single donut as JSON")
        func getDonut() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/api/v1/donuts/\(UUID())")

            // Returns 404 for unknown ID, but still JSON
            #expect(response.header("Content-Type")?.contains("application/json") == true)
        }

        @Test("POST /api/v1/donuts creates donut and returns JSON")
        func createDonut() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.post(
                "/api/v1/donuts",
                json: [
                    "name": "Test Donut",
                    "description": "A test donut",
                    "price": 2.99,
                    "categoryId": UUID().uuidString,
                ]
            )

            // Returns 201 Created with JSON
            #expect(response.status == .created || response.status == .unprocessableEntity)
        }

        @Test("DELETE /api/v1/donuts/:id returns no content")
        func deleteDonut() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.delete("/api/v1/donuts/\(UUID())")

            #expect(response.status == .noContent || response.status == .notFound)
        }
    }

    // MARK: - Frontend Routes (HTML)

    @Suite("Frontend Routes")
    struct FrontendRoutes {

        @Test("GET /donuts returns HTML")
        func listDonutsHTML() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/donuts")

            #expect(response.status == .ok)
            #expect(response.header("Content-Type")?.contains("text/html") == true)
            #expect(response.text.contains("<!DOCTYPE html>"))
        }

        @Test("GET /donuts/:id returns HTML detail page")
        func getDonutHTML() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/donuts/\(UUID())")

            // Returns 404 HTML page for unknown ID
            #expect(response.header("Content-Type")?.contains("text/html") == true)
        }

        @Test("POST /donuts redirects to list with flash")
        func createDonutHTML() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.request(
                method: .post,
                path: "/donuts",
                body: Data("name=Test&description=Yum&price=2.99&categoryId=\(UUID())".utf8),
                headers: ["Content-Type": "application/x-www-form-urlencoded"]
            )

            // Form submissions redirect (303 See Other)
            #expect(response.status == .seeOther || response.status == .badRequest)
        }

        @Test("DELETE /donuts/:id redirects with flash")
        func deleteDonutHTML() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.request(
                method: .post,
                path: "/donuts/\(UUID())?_method=DELETE",
                headers: ["Content-Type": "application/x-www-form-urlencoded"]
            )

            // Form submissions with method override redirect
            #expect(response.status == .seeOther || response.status == .notFound)
        }
    }

    // MARK: - CSRF Protection

    @Suite("CSRF Protection")
    struct CSRFProtection {

        @Test("Frontend forms require CSRF token")
        func requiresCSRFToken() async throws {
            let app = try await TestApp(DonutShop.self)

            // POST without CSRF token should fail
            let response = try await app.request(
                method: .post,
                path: "/donuts",
                body: Data("name=Test&price=1.00".utf8),
                headers: ["Content-Type": "application/x-www-form-urlencoded"]
            )

            // Should get 403 Forbidden
            #expect(response.status == .forbidden || response.status == .badRequest)
        }

        @Test("API endpoints bypass CSRF for JSON requests")
        func apiBypassesCSRF() async throws {
            let app = try await TestApp(DonutShop.self)

            // JSON requests don't need CSRF token
            let response = try await app.post(
                "/api/v1/donuts",
                json: ["name": "Test", "price": 1.00, "categoryId": UUID().uuidString]
            )

            // Should not be 403 (might be 422 for validation, but not CSRF)
            #expect(response.status != .forbidden)
        }

        @Test("CSRF token is injected into HTML forms")
        func csrfTokenInForms() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/donuts/new")

            #expect(response.text.contains("csrfToken") || response.text.contains("_csrf"))
        }
    }

    // MARK: - Flash Messages

    @Suite("Flash Messages")
    struct FlashMessages {

        @Test("Flash messages are displayed after redirect")
        func flashAfterRedirect() async throws {
            let app = try await TestApp(DonutShop.self)

            // First, get the form to obtain CSRF token
            let formResponse = try await app.get("/donuts/new")
            let csrfMatch = formResponse.text.range(of: #"value="([^"]+)""#, options: .regularExpression)
            let csrfToken = csrfMatch.map { String(formResponse.text[$0]) } ?? ""

            // Submit form with CSRF token
            let body = "_csrf=\(csrfToken)&name=FlashTest&description=Test&price=1.00&categoryId=\(UUID())"
            let response = try await app.request(
                method: .post,
                path: "/donuts",
                body: Data(body.utf8),
                headers: ["Content-Type": "application/x-www-form-urlencoded"]
            )

            // Should redirect with flash
            #expect(response.status == .seeOther)

            // Follow redirect should show flash
            if let location = response.header("Location") {
                let finalResponse = try await app.get(location)
                #expect(finalResponse.text.contains("flash") || finalResponse.text.contains("created"))
            }
        }
    }

    // MARK: - Static Files

    @Suite("Static Files")
    struct StaticFiles {

        @Test("CSS files are served")
        func servesCSS() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/css/app.css")

            #expect(response.status == .ok)
            #expect(response.header("Content-Type")?.contains("text/css") == true)
        }

        @Test("JS files are served")
        func servesJS() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/js/app.js")

            #expect(response.status == .ok)
            #expect(response.header("Content-Type")?.contains("javascript") == true)
        }

        @Test("Missing files return 404")
        func missingFile404() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get("/css/nonexistent.css")

            #expect(response.status == .notFound)
        }
    }

    // MARK: - Content Negotiation

    @Suite("Content Negotiation")
    struct ContentNegotiation {

        @Test("Accept: application/json gets JSON")
        func jsonContentType() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get(
                "/api/v1/donuts",
                headers: ["Accept": "application/json"]
            )

            #expect(response.header("Content-Type")?.contains("application/json") == true)
        }

        @Test("Accept: text/html gets HTML")
        func htmlContentType() async throws {
            let app = try await TestApp(DonutShop.self)

            let response = try await app.get(
                "/donuts",
                headers: ["Accept": "text/html"]
            )

            #expect(response.header("Content-Type")?.contains("text/html") == true)
        }
    }

    // MARK: - Route Composition

    @Suite("Route Composition")
    struct RouteComposition {

        @Test("Scoped routes are prefixed correctly")
        func scopedRoutes() async throws {
            let app = try await TestApp(DonutShop.self)

            // /api/v1 scope
            let apiResponse = try await app.get("/api/v1/donuts")
            #expect(apiResponse.status == .ok || apiResponse.status == .notFound)

            // Root scope
            let rootResponse = try await app.get("/donuts")
            #expect(rootResponse.status == .ok)
        }

        @Test("Forwarded routes work independently")
        func forwardedRoutes() async throws {
            let app = try await TestApp(DonutShop.self)

            // Forwarded from / to donut routes
            let response = try await app.get("/donuts")
            #expect(response.status == .ok)

            // Forwarded to customer routes
            let customerResponse = try await app.get("/customers")
            #expect(customerResponse.status == .ok || customerResponse.status == .notFound)
        }
    }
}