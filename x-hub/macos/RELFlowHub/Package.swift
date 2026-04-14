// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RELFlowHub",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "RELFlowHubCore", targets: ["RELFlowHubCore"]),
        .executable(name: "RELFlowHub", targets: ["RELFlowHub"]),
        .executable(name: "XHub", targets: ["RELFlowHub"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "RELFlowHubCore"),
        .executableTarget(
            name: "RELFlowHub",
            dependencies: ["RELFlowHubCore"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "RELFlowHubCoreTests",
            dependencies: ["RELFlowHubCore"]
        ),
        .testTarget(
            name: "RELFlowHubAppTests",
            dependencies: ["RELFlowHub", "RELFlowHubCore"]
        ),
    ]
)
