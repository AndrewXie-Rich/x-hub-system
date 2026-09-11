// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XTGoldenProject",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GoldenProject", targets: ["GoldenProject"]),
        .executable(name: "GoldenProjectTests", targets: ["GoldenProjectTests"]),
    ],
    targets: [
        .target(name: "GoldenProject"),
        .executableTarget(name: "GoldenProjectTests", dependencies: ["GoldenProject"]),
        .testTarget(name: "GoldenProjectAcceptanceTests", dependencies: ["GoldenProject"]),
    ]
)
