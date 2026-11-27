// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Smolix",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure scroll math, no AppKit — unit tested.
        .target(name: "SmolixCore"),
        // The menu bar app.
        .executableTarget(
            name: "Smolix",
            dependencies: ["SmolixCore"]
        ),
        .testTarget(
            name: "SmolixCoreTests",
            dependencies: ["SmolixCore"]
        ),
    ]
)
