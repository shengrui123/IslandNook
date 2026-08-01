// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IslandNook",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "IslandNook", targets: ["IslandNook"])],
    targets: [
        .executableTarget(
            name: "IslandNook",
            path: "Sources/IslandNook",
            resources: [.process("Resources")]
        )
    ]
)
