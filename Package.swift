// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tabby",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TabbyCore"),
        // Swift 5 language mode: the app is full of C callbacks (event tap, CoreGraphics, AX)
        // where Swift 6 strict concurrency adds noise without catching real bugs.
        .executableTarget(
            name: "Tabby",
            dependencies: ["TabbyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "TabbyCoreTests", dependencies: ["TabbyCore"]),
    ]
)
