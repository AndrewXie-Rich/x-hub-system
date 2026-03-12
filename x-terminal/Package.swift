// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XTerminal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "XTerminal", targets: ["XTerminal"])
    ],
    targets: [
        .executableTarget(
            name: "XTerminal",
            path: "Sources",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "XTerminalTests",
            dependencies: ["XTerminal"],
            path: "Tests"
        ),
    ]
)
