import Foundation

enum Platform {
    /// Returns the Tailwind CSS binary name for the current OS and architecture.
    static var tailwindBinaryName: String {
        #if os(macOS)
            #if arch(arm64)
                return "tailwindcss-macos-arm64"
            #else
                return "tailwindcss-macos-x64"
            #endif
        #else
            #if arch(arm64)
                return "tailwindcss-linux-arm64"
            #else
                return "tailwindcss-linux-x64"
            #endif
        #endif
    }
}
