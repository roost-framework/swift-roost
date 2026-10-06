// swift-tools-version: 6.3

import PackageDescription
import Foundation

// This in-repository example uses its containing framework checkout, including
// when an editor evaluates the manifest without the helper's environment.
let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let ecosystem = ProcessInfo.processInfo.environment["ROOST_ECOSYSTEM_PATH"]
let frameworkPath = ProcessInfo.processInfo.environment["ROOST_FRAMEWORK_PATH"]
    ?? ecosystem.map { "\($0)/Roost" }
    ?? checkout.path
let frameworkDependency: Package.Dependency = .package(name: "swift-roost", path: frameworkPath)
let eswPath = ProcessInfo.processInfo.environment["ROOST_ESW_PATH"]
    ?? ecosystem.map { "\($0)/esw" }
let eswDependency: Package.Dependency = eswPath.map {
    .package(name: "esw", path: $0)
} ?? .package(url: "https://github.com/Spectro-ORM/ESW.git", from: "1.5.0")

let package = Package(
    name: "RoostExample",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        frameworkDependency,
        eswDependency,
    ],
    targets: [
        .executableTarget(
            name: "RoostExample",
            dependencies: [
                .product(name: "Roost", package: "swift-roost"),
                .product(name: "ESW", package: "esw"),
            ],
            plugins: [
                .plugin(name: "ESWBuildPlugin", package: "esw"),
            ]
        ),
        .testTarget(
            name: "RoostExampleTests",
            dependencies: [
                "RoostExample",
                .product(name: "RoostTest", package: "swift-roost"),
            ]
        ),
    ]
)
