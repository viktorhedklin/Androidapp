// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GameAutopilotMac",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GameAutopilotMac",
            path: "Sources/GameAutopilotMac"
        )
    ]
)
