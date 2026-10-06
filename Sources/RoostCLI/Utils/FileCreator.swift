import Foundation
@preconcurrency import Noora

enum FileCreator {
    struct Conflict: Error, CustomStringConvertible {
        let path: String
        var description: String { "Refusing to overwrite '\(path)'. Rename the resource or move the existing file first." }
    }

    static func checkAvailable(_ paths: [String], in baseDir: String) throws {
        for path in paths {
            if FileManager.default.fileExists(atPath: (baseDir as NSString).appendingPathComponent(path)) {
                throw Conflict(path: path)
            }
        }
    }

    static func create(_ files: [(String, String)], in baseDir: String) throws {
        try checkAvailable(files.map(\.0), in: baseDir)
        for (path, content) in files { try create(at: path, in: baseDir, content: content) }
    }

    /// Creates a file at the given path relative to `baseDir`, logging with Noora.
    static func create(
        at relativePath: String,
        in baseDir: String,
        content: String
    ) throws {
        let fullPath = (baseDir as NSString).appendingPathComponent(relativePath)
        try checkAvailable([relativePath], in: baseDir)
        let dir = (fullPath as NSString).deletingLastPathComponent

        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: URL(fileURLWithPath: fullPath), options: .withoutOverwriting)

        RoostUI.noora.success(.alert("create  \(.muted(relativePath))"))
    }
}
