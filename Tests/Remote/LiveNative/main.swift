import Foundation
import CryptoKit

// Explicit live-test entry point. Credentials stay in memory, read from the
// supplied export. Only a new UUID directory under this account is modified.
guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: live /path/to/FileZilla.xml host /path/to/problematic-files")
}
let host = CommandLine.arguments[2]
let matches = try FileZillaImport.loadConnections(from: URL(fileURLWithPath: CommandLine.arguments[1])).filter { $0.host.lowercased() == host.lowercased() && [0, 3, 4].contains($0.protocolType) }
guard matches.count == 1 else { fatalError("Expected one matching FTP profile") }
let connection = matches[0]
let root = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-live-native-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let actualTrust = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("macmd/Trust")
RemoteTrust.testDirectory = root
let key = "\(connection.protocolType):\(connection.host.lowercased()):\(connection.port)"
let filename = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") + ".exception.pem"
try FileManager.default.copyItem(at: actualTrust.appendingPathComponent(filename), to: root.appendingPathComponent(filename))
RemoteTrust.testApproval = { (false, false) } // Never silently approve a new certificate.
RemoteTrust.beginTLSBatch()
defer { RemoteTrust.endTLSBatch() }
let remoteName = ".macmd-native-test-" + UUID().uuidString
let remoteRoot = FTPBrowser.childPath(parent: connection.initialPath, child: remoteName)
let sources = URL(fileURLWithPath: CommandLine.arguments[3])
let names = ["innsbruck.html", "osnova-innsbruck.md", "resers-innsbruck.md"]
var successful = 0
var failure: Error?
let began = Date()
do {
    try FTPBrowser.createDirectory(connection: connection, parentPath: connection.initialPath, name: remoteName)
    for round in 1...3 {
        for name in names {
            let source = sources.appendingPathComponent(name)
            let remote = FTPBrowser.childPath(parent: remoteRoot, child: name)
            let start = Date()
            try FTPBrowser.upload(connection: connection, localURL: source, to: remote)
            let destination = root.appendingPathComponent("readback")
            try FTPBrowser.download(connection: connection, remotePath: remote, isDirectory: false, to: destination)
            guard try SHA256.hash(data: Data(contentsOf: source)) == SHA256.hash(data: Data(contentsOf: destination)) else {
                throw RemoteTrust.error("Readback content differs")
            }
            successful += 1
            print("PASS native round \(round): \(name), SHA-256 matched, \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
        }
    }
    // An independent tree exercises UTF-8, spaces, recursion and atomic overwrite.
    let tree = root.appendingPathComponent("tree # č😀")
    try FileManager.default.createDirectory(at: tree.appendingPathComponent("sub folder"), withIntermediateDirectories: true)
    try Data(repeating: 91, count: 1_000_000).write(to: tree.appendingPathComponent("sub folder/payload # ü.bin"))
    try FTPBrowser.upload(connection: connection, localURL: tree, to: FTPBrowser.childPath(parent: remoteRoot, child: tree.lastPathComponent))
    let downloaded = root.appendingPathComponent("tree download")
    try FTPBrowser.download(connection: connection, remotePath: FTPBrowser.childPath(parent: remoteRoot, child: tree.lastPathComponent), isDirectory: true, to: downloaded)
    guard try Data(contentsOf: downloaded.appendingPathComponent("sub folder/payload # ü.bin")) == Data(contentsOf: tree.appendingPathComponent("sub folder/payload # ü.bin")) else { throw RemoteTrust.error("Tree readback differs") }
    print("PASS native: recursive UTF-8/spaced paths and 1 MB binary readback")
} catch { failure = error }
let directories = try FTPBrowser.list(connection: connection, path: connection.initialPath).filter { $0.name == remoteName }
guard directories.count == 1 else { fatalError("Could not identify the UUID test directory for cleanup: \(remoteRoot)") }
try FTPBrowser.delete(connection: connection, items: directories, basePath: connection.initialPath)
let remaining = try FTPBrowser.list(connection: connection, path: connection.initialPath)
guard !remaining.contains(where: { $0.name == remoteName }) else { fatalError("Live test directory remains: \(remoteRoot)") }
print("PASS: live test directory removed")
if let failure { throw failure }
print("PASS: \(successful) exact-source uploads + readbacks and recursive binary transfer in \(String(format: "%.2f", Date().timeIntervalSince(began))) s")
print("Engine: \(NativeFTPTransport.version)")
