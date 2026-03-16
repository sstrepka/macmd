// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macmd",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "macmd",
            path: "Sources/macmd"
        )
    ]
)
