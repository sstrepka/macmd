// swift-tools-version: 5.8
import PackageDescription
import Foundation

// Run scripts/prepare_ftp_engine.sh before building. The packaged app links the
// same pinned static engine via build.sh and has no Homebrew runtime dependency.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let engine = root + "/.build/ftp-deps"
let package = Package(
    name: "macmd",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CNativeFTP",
            path: "Sources/CNativeFTP",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I" + engine + "/include"])],
            linkerSettings: [
                .unsafeFlags([engine + "/lib/libcurl.a", engine + "/lib/libssl.a", engine + "/lib/libcrypto.a"]),
                .linkedFramework("SystemConfiguration"), .linkedFramework("CoreFoundation"), .linkedFramework("CoreServices")
            ]
        ),
        .executableTarget(name: "macmd", dependencies: ["CNativeFTP"], path: "Sources/macmd")
    ]
)
