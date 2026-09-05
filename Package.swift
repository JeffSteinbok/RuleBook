// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RuleBook",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RuleBookKit", targets: ["RuleBookKit"]),
        .executable(name: "rulebook", targets: ["rulebook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Pure Swift + Foundation only. No UIKit/SwiftUI/AppKit imports here,
        // so this target builds unchanged for macOS CLI, iOS, and the Simulator.
        .target(name: "RuleBookKit"),
        .executableTarget(
            name: "rulebook",
            dependencies: [
                "RuleBookKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RuleBookKitTests",
            dependencies: ["RuleBookKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
