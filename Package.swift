// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TotalCmd",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TotalCmd",
            path: "Sources/TotalCmd"
        )
    ]
)
