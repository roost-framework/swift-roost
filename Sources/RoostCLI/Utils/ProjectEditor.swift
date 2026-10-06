import Foundation

/// Only edit explicit insertion points in a generated app. Handwritten files
/// remain owned by the developer, and an unsupported structure fails before generation.
enum ProjectEditor {
    struct MissingMarker: Error, CustomStringConvertible {
        let marker: String
        var description: String { "Add '// roost:\(marker)' inside App.swift's \(marker) declaration, then rerun the generator." }
    }

    static func registeredApp(in context: ProjectContext, routes: [String], plugs: [String] = []) throws -> (String, String) {
        let path = "Sources/\(context.appName)/App.swift"
        let full = (context.root as NSString).appendingPathComponent(path)
        var content = try String(contentsOfFile: full, encoding: .utf8)
        for (kind, additions) in [("routes", routes), ("plugs", plugs)] where !additions.isEmpty {
            let marker = "// roost:\(kind)"
            guard content.contains(marker) else { throw MissingMarker(marker: kind) }
            content = content.replacingOccurrences(of: marker, with: additions.joined(separator: "\n        ") + "\n        " + marker)
        }
        return (full, content)
    }

    static func nextMigration(in root: String, description: String, offset: Int = 0) -> String {
        let directory = ProjectDiscovery.migrationsDir(root: root)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let latest = files.compactMap { Int64($0.split(separator: "_").first ?? "") }.max() ?? 0
        // Spectro migration versions use Unix seconds, not calendar timestamps.
        let now = Int64(Date().timeIntervalSince1970)
        return "\(max(now, latest + 1) + Int64(offset))_\(description).sql"
    }
}
