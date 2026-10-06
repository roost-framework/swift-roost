import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@preconcurrency import Noora

enum Downloader {
    /// Downloads a file from the given URL and writes it to the destination path.
    /// Creates intermediate directories if needed.
    static func download(from url: URL, to destination: String) async throws {
        let dir = (destination as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw DownloadError.httpError(statusCode: httpResponse.statusCode, url: url)
        }

        try data.write(to: URL(fileURLWithPath: destination))
    }

    enum DownloadError: LocalizedError {
        case httpError(statusCode: Int, url: URL)

        var errorDescription: String? {
            switch self {
            case .httpError(let statusCode, let url):
                return "Download failed with status \(statusCode): \(url.absoluteString)"
            }
        }
    }
}
