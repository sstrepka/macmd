import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-remote-harness-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let fixture = root.appendingPathComponent("sites.xml")
let xml = """
<FileZilla3><Servers><Folder>Testing &amp; QA<Server><Host>127.0.0.1</Host><Port>21210</Port><Protocol>0</Protocol><Type>0</Type><User>tester</User><Pass encoding="base64">c2VjcmV0</Pass><Logontype>1</Logontype><Name>A &amp; B</Name><RemoteDir>1 0 11 folder name </RemoteDir><LocalDir>/tmp/local</LocalDir><MaximumMultipleConnections>3</MaximumMultipleConnections><Future><Option>keep me</Option></Future></Server></Folder><Server><Host>encrypted.example</Host><Protocol>1</Protocol><Pass encoding="crypt" pubkey="xyz">opaque</Pass><Name>Encrypted</Name></Server></Servers></FileZilla3>
"""
try xml.write(to: fixture, atomically: true, encoding: .utf8)
let imported = try FileZillaImport.loadConnections(from: fixture)
expect(imported.count == 2, "site count")
expect(imported[0].password == "secret", "base64 password")
expect(imported[0].initialPath == "/folder name", "path containing spaces")
expect(imported[0].fileZillaFolders == ["Testing & QA"], "folder hierarchy")
expect(imported[1].password.isEmpty, "encrypted password must not become login password")
expect(FileZillaImport.decodeRemoteDir("1 0 2 a😀 1 x") == "/a😀/x", "FileZilla UTF-32 safe path")
expect(FileZillaImport.decodeRemoteDir("1 0 3 a😀 1 x") == "/a😀/x", "FileZilla UTF-16 safe path")
expect(FileZillaImport.encodeRemoteDir("/folder name") == "1 0 11 folder name", "canonical FileZilla safe path")
let exported = root.appendingPathComponent("export.xml")
try FileZillaImport.export(imported, to: exported)
let roundtrip = try FileZillaImport.loadConnections(from: exported)
expect(roundtrip[0].password == "secret", "password roundtrip")
let exportedText = try String(contentsOf: exported)
expect(exportedText.contains("MaximumMultipleConnections") && exportedText.contains("keep me") && exportedText.contains("opaque"), "extra fields preserved")
for path in ["/", "/folder name/ďalší adresár", "/a😀/x"] {
    expect(FileZillaImport.decodeRemoteDir(FileZillaImport.encodeRemoteDir(path)) == path, "Unicode path roundtrip")
}
print("PASS: FileZilla roundtrip, folder hierarchy, unknown fields, encrypted password preservation, Unicode paths")

if CommandLine.arguments.count > 1 {
    let proto = Int(CommandLine.arguments[1])!
    let port = Int(CommandLine.arguments[2])!
    let certificateURL = RemoteTrust.directory.appendingPathComponent(Data("127.0.0.1:\(port)".utf8).base64EncodedString() + ".pem")
    if [3, 4].contains(proto) { try FileManager.default.copyItem(at: URL(fileURLWithPath: "/tmp/macmd-test-tls.pem"), to: certificateURL) }
    defer { if [3, 4].contains(proto) { try? FileManager.default.removeItem(at: certificateURL) } }
    let testKey = proto == 1 ? try String(contentsOfFile: "/tmp/macmd-test-knownhost") : ""
    if !testKey.isEmpty {
        let original = (try? String(contentsOf: RemoteTrust.knownHosts)) ?? ""
        try (original + testKey).write(to: RemoteTrust.knownHosts, atomically: true, encoding: .utf8)
    }
    defer {
        if !testKey.isEmpty, let current = try? String(contentsOf: RemoteTrust.knownHosts) {
            try? current.replacingOccurrences(of: testKey, with: "").write(to: RemoteTrust.knownHosts, atomically: true, encoding: .utf8)
        }
    }
    let connection = FTPConnection(name: "Harness", host: "127.0.0.1", port: port, username: "tester", password: "secret", protocolType: proto, logonType: 1)
    Thread.current.threadDictionary["macmd.remote.cancel"] = { true } as () -> Bool
    do {
        _ = try FTPBrowser.list(connection: connection, path: "/")
        fatalError("Cancelled operation must fail")
    } catch {}
    Thread.current.threadDictionary.removeObject(forKey: "macmd.remote.cancel")
    let source = root.appendingPathComponent("input")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let data = Data(repeating: 65, count: 180_000)
    try data.write(to: source.appendingPathComponent("file # ü.txt"))
    try FTPBrowser.upload(connection: connection, localURL: source, to: "/transport test")
    let listing = try FTPBrowser.list(connection: connection, path: "/transport test")
    expect(listing.contains { $0.name == "file # ü.txt" && $0.size == 180_000 }, "remote listing")
    try FTPBrowser.rename(connection: connection, from: "/transport test/file # ü.txt", to: "/transport test/renamed.txt")
    try FTPBrowser.chmod(connection: connection, path: "/transport test/renamed.txt", mode: "640")
    let destination = root.appendingPathComponent("download")
    try FTPBrowser.download(connection: connection, remotePath: "/transport test", isDirectory: true, to: destination)
    let downloaded = try Data(contentsOf: destination.appendingPathComponent("renamed.txt"))
    expect(downloaded == data, "download bytes")
    // Replacing an existing file uses a staging file and atomic local commit.
    try FTPBrowser.download(connection: connection, remotePath: "/transport test/renamed.txt", isDirectory: false, to: destination.appendingPathComponent("renamed.txt"))
    let protected = root.appendingPathComponent("existing")
    try Data("original".utf8).write(to: protected)
    do {
        try FTPBrowser.download(connection: connection, remotePath: "/missing-file", isDirectory: false, to: protected)
        fatalError("missing download must fail")
    } catch {}
    let preserved = try String(contentsOf: protected)
    expect(preserved == "original", "failed download preserves existing file")
    do {
        try FTPBrowser.rename(connection: connection, from: "/missing-file", to: "/nope")
        fatalError("missing rename must fail")
    } catch {}
    try FTPBrowser.createDirectory(connection: connection, parentPath: "/", name: "relay")
    try FTPBrowser.relayCopy(connection: connection, remotePath: "/transport test", isDirectory: true, to: connection, targetDirectoryPath: "/relay")
    let relay = try FTPBrowser.list(connection: connection, path: "/relay/transport test")
    expect(relay.contains { $0.name == "renamed.txt" }, "relay copy")
    try FTPBrowser.delete(connection: connection, items: try FTPBrowser.list(connection: connection, path: "/").filter { $0.name == "transport test" || $0.name == "relay" }, basePath: "/")
    print("PASS: protocol \(proto): recursive upload, listing, rename, recursive download, failure preservation, error propagation, relay copy, recursive delete")
}
