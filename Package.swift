// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowShelf",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FlowShelf",
            path: "Sources/FlowShelf"
        )
    ]
)
