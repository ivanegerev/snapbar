// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SnapBar",
            path: "Sources/SnapBar"
        )
    ]
)
