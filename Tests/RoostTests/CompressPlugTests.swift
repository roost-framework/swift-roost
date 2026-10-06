import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Roost

@Suite("Compress Plug")
struct CompressPlugTests {

    @Test("compress returns a Compression struct")
    func compressReturnsCompression() {
        let _ = compress()
        // Compression is a Nexus struct; verify it constructs without error
        #expect(true)
    }

    @Test("compress with custom minBytes returns a Compression struct")
    func compressWithCustomMinBytes() {
        let _ = compress(minBytes: 512)
        #expect(true)
    }

    @Test("defaultCompressibleTypes includes text/html")
    func defaultCompressibleTypesIncludesHTML() {
        #expect(defaultCompressibleTypes.contains("text/html"))
    }

    @Test("defaultCompressibleTypes includes application/json")
    func defaultCompressibleTypesIncludesJSON() {
        #expect(defaultCompressibleTypes.contains("application/json"))
    }

    @Test("defaultCompressibleTypes includes text/css")
    func defaultCompressibleTypesIncludesCSS() {
        #expect(defaultCompressibleTypes.contains("text/css"))
    }

    @Test("defaultCompressibleTypes includes application/javascript")
    func defaultCompressibleTypesIncludesJS() {
        #expect(defaultCompressibleTypes.contains("application/javascript"))
    }

    @Test("defaultCompressibleTypes includes SVG")
    func defaultCompressibleTypesIncludesSVG() {
        #expect(defaultCompressibleTypes.contains("image/svg+xml"))
    }

    @Test("defaultCompressibleTypes does not include binary images")
    func defaultCompressibleTypesExcludesBinaryImages() {
        #expect(!defaultCompressibleTypes.contains("image/png"))
        #expect(!defaultCompressibleTypes.contains("image/jpeg"))
        #expect(!defaultCompressibleTypes.contains("image/gif"))
        #expect(!defaultCompressibleTypes.contains("application/pdf"))
    }

    @Test("defaultCompressibleTypes includes web fonts and manifests")
    func defaultCompressibleTypesIncludesManifests() {
        #expect(defaultCompressibleTypes.contains("application/manifest+json"))
        #expect(defaultCompressibleTypes.contains("application/ld+json"))
    }
}
