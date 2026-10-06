import Foundation

/// Manages child processes for the dev server.
final class ProcessManager: @unchecked Sendable {
    private var serverProcess: Process?
    private var tailwindProcess: Process?

    static func binaryPath(product: String, root: String) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build", "--show-bin-path"]
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { throw BinaryPathError() }
        return (path as NSString).appendingPathComponent(product)
    }

    private struct BinaryPathError: Error {}

    /// Start the server binary.
    func startServer(binary: String, port: Int?, cwd: String? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        if let port {
            var environment = ProcessInfo.processInfo.environment
            environment["ROOST_PORT"] = String(port)
            process.environment = environment
        }

        do {
            try process.run()
            serverProcess = process
        } catch {
            print("[roost] Failed to start server: \(error.localizedDescription)")
        }
    }

    /// Stop the server (SIGTERM, wait up to 2s, then SIGKILL).
    func stopServer() {
        guard let process = serverProcess, process.isRunning else {
            serverProcess = nil
            return
        }

        process.terminate()

        let semaphore = DispatchSemaphore(value: 0)
        let workItem = DispatchWorkItem {
            process.waitUntilExit()
            semaphore.signal()
        }
        DispatchQueue.global().async(execute: workItem)

        let result = semaphore.wait(timeout: .now() + 2.0)
        if result == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }

        serverProcess = nil
    }

    /// Start Tailwind in watch mode.
    func startTailwind(binary: String, cwd: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-i", "Public/css/input.css", "-o", "Public/css/app.css", "--watch"]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            tailwindProcess = process
        } catch {
            print("[roost] Failed to start Tailwind: \(error.localizedDescription)")
        }
    }

    /// Stop all processes.
    func stopAll() {
        if let tw = tailwindProcess, tw.isRunning {
            tw.terminate()
            tw.waitUntilExit()
            tailwindProcess = nil
        }
        stopServer()
    }
}
