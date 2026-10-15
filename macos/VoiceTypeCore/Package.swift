// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VoiceTypeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .executable(name: "CoreDemo", targets: ["CoreDemo"]),
    ],
    targets: [
        .target(
            name: "Core",
            path: "Sources/Core",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "CoreDemo",
            dependencies: ["Core"],
            path: "Sources/CoreDemo"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
    ]
)
