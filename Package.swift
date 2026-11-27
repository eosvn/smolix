// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Smolix",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates from GitHub Releases (appcast signed with EdDSA).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure scroll math, no AppKit — unit tested.
        .target(name: "SmolixCore"),
        // The menu bar app.
        .executableTarget(
            name: "Smolix",
            dependencies: [
                "SmolixCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "SmolixCoreTests",
            dependencies: ["SmolixCore"]
        ),
    ]
)
