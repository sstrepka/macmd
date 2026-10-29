import Foundation
let root = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-upload-test-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
RemoteTrust.testDirectory = root
RemoteTrust.testApproval = { (true, false) }
RemoteTrust.beginTLSBatch()
defer { RemoteTrust.endTLSBatch() }
let site = FTPConnection(name: "Test", host: "127.0.0.1", port: 21212, username: "tester", password: "secret", protocolType: 0)
let source = root.appendingPathComponent("source.txt")
let payload = Data(String(repeating: "Verified UTF-8 payload čšč😀\n", count: 1000).utf8)
try payload.write(to: source)
let expectFailure = CommandLine.arguments.contains("--expect-failure") || CommandLine.arguments.contains("--expect-rename-failure")
var failed = false
do { try FTPBrowser.upload(connection: site, localURL: source, to: "/final.txt") }
catch { failed = true; print(error.localizedDescription); precondition((error as NSError).code == (CommandLine.arguments.contains("--expect-rename-failure") ? 21 : 18)) }
precondition(failed == expectFailure)
let target = root.appendingPathComponent("target.txt")
try FTPBrowser.download(connection: site, remotePath: "/final.txt", isDirectory: false, to: target)
let actual = try Data(contentsOf: target)
precondition(actual == (expectFailure ? Data("previous contents".utf8) : payload))
let listing = try FTPBrowser.list(connection: site, path: "/")
precondition(!listing.contains { $0.name.hasPrefix(".macmd-upload-") })
print(expectFailure ? "PASS: failed upload preserves final file and removes staging" : "PASS: normal/recovered upload has exact contents and no staging files")
