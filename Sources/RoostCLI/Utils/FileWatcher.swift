import Foundation

/// Watches directories for file changes using polling.
final class FileWatcher: @unchecked Sendable {
    /// Directories to watch recursively
    private let watchPaths: [String]
    /// File extensions to monitor
    private let extensions: Set<String>
    /// Debounce interval in seconds
    private let debounceInterval: TimeInterval
    /// Callback when changes detected
    private let onChange: ([String]) -> Void

    /// Tracks last known modification times
    private var knownFiles: [String: Date] = [:]
    private var running = true

    init(
        paths: [String],
        extensions: Set<String>,
        debounceInterval: TimeInterval = 0.3,
        onChange: @escaping ([String]) -> Void
    ) {
        self.watchPaths = paths
        self.extensions = extensions
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    /// Start polling loop (blocks the calling thread).
    func start() {
        // Build initial snapshot
        knownFiles = scanAll()

        while running {
            Thread.sleep(forTimeInterval: 0.5)
            guard running else { break }

            let current = scanAll()
            var changed: [String] = []

            for (path, modDate) in current {
                if let known = knownFiles[path] {
                    if modDate > known {
                        changed.append(path)
                    }
                } else {
                    // New file
                    changed.append(path)
                }
            }

            changed.append(contentsOf: knownFiles.keys.filter { current[$0] == nil })

            if !changed.isEmpty {
                // Debounce: wait then re-scan to collect burst of saves
                Thread.sleep(forTimeInterval: debounceInterval)
                let afterDebounce = scanAll()
                var allChanged: [String] = changed

                for (path, modDate) in afterDebounce {
                    if let prev = current[path], modDate > prev, !allChanged.contains(path) {
                        allChanged.append(path)
                    }
                }

                knownFiles = afterDebounce
                onChange(allChanged)
            } else {
                knownFiles = current
            }
        }
    }

    /// Stop the watcher.
    func stop() {
        running = false
    }

    // MARK: - Private

    private func scanAll() -> [String: Date] {
        var result: [String: Date] = [:]
        let fm = FileManager.default

        for watchPath in watchPaths {
            guard let enumerator = fm.enumerator(atPath: watchPath) else { continue }

            while let relative = enumerator.nextObject() as? String {
                // Skip temp files
                let filename = (relative as NSString).lastPathComponent
                if filename.hasPrefix(".#") { continue }
                if filename.hasSuffix(".swp") || filename.hasSuffix("~") || filename.hasSuffix(".tmp") {
                    continue
                }

                let ext = (relative as NSString).pathExtension
                guard extensions.contains(ext) else { continue }

                let fullPath = (watchPath as NSString).appendingPathComponent(relative)
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let modDate = attrs[.modificationDate] as? Date
                {
                    result[fullPath] = modDate
                }
            }
        }

        return result
    }
}
