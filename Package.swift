// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentLens",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentLens", targets: ["AgentLens"])
    ],
    targets: [
        .executableTarget(
            name: "AgentLens",
            path: "Sources/AgentLens"
        )
    ]
)
