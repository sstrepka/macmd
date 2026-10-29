import Foundation

func check(_ value: Bool, line: UInt = #line) { precondition(value, "TLS regression failed at line \(line)") }

let root = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-tls-regression-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
RemoteTrust.testDirectory = root
func makeCertificate(_ name: String) throws -> String {
    let pem = root.appendingPathComponent(name + ".pem")
    let result = try RemoteTrust.run("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=" + name, "-keyout", root.appendingPathComponent(name + ".key").path, "-out", pem.path])
    check(result.0 == 0)
    return try String(contentsOf: pem)
}
let original = try makeCertificate("wrong-host.example")
let changed = try makeCertificate("changed.example")
var current = original
var prompts = 0
var probes = 0
var decision = (true, false)
RemoteTrust.testCertificate = { probes += 1; return current }
RemoteTrust.testApproval = { prompts += 1; return decision }
let site = FTPConnection(name: "Test", host: "127.0.0.1", port: 21212, username: "tester", password: "secret", protocolType: 0)
check(try RemoteTrust.tlsExceptionOptions(site).isEmpty)
try RemoteTrust.trustCertificate(site)
check(prompts == 1)
let options = try RemoteTrust.tlsExceptionOptions(site)
check(options.contains("--insecure") && options.contains("--ssl-reqd") && options.contains("--pinnedpubkey"))
let pin = options[options.firstIndex(of: "--pinnedpubkey")! + 1]
check(pin.hasPrefix("sha256//") && Data(base64Encoded: String(pin.dropFirst(8)))?.count == 32)
check(prompts == 1)
check(!((try FileManager.default.contentsOfDirectory(atPath: root.path)).contains { $0.hasSuffix(".exception.pem") }))
let beforeBatch = probes
RemoteTrust.beginTLSBatch()
check(try RemoteTrust.tlsExceptionOptions(site) == options)
check(try RemoteTrust.tlsExceptionOptions(site) == options)
check(probes == beforeBatch + 1)
RemoteTrust.endTLSBatch()
check(try RemoteTrust.tlsExceptionOptions(site) == options)
check(probes == beforeBatch + 2)
var other = site
other.host = "other.example"
check(try RemoteTrust.tlsExceptionOptions(other).isEmpty)
other = site; other.port += 1
check(try RemoteTrust.tlsExceptionOptions(other).isEmpty)
other = site; other.protocolType = 4
check(try RemoteTrust.tlsExceptionOptions(other).isEmpty)
current = changed; decision = (false, false)
do { _ = try RemoteTrust.tlsExceptionOptions(site); preconditionFailure("Changed certificate accepted after cancellation") }
catch { check(prompts == 2) }
decision = (true, true)
let newOptions = try RemoteTrust.tlsExceptionOptions(site)
check(newOptions != options && prompts == 3)
check((try FileManager.default.contentsOfDirectory(atPath: root.path)).contains { $0.hasSuffix(".exception.pem") })
try RemoteTrust.forgetTLSException(site)
check(try RemoteTrust.tlsExceptionOptions(site).isEmpty)
print("PASS: session and saved TLS exceptions, host/port/protocol isolation, exact certificate change, cancellation, key pin and reset")

if CommandLine.arguments.contains("--local-server") {
    RemoteTrust.testCertificate = nil
    decision = (true, false)
    let before = prompts
    _ = try FTPBrowser.list(connection: site, path: "/")
    check(prompts == before + 1)
    let source = root.appendingPathComponent("upload.txt")
    try Data("TLS exception transfer".utf8).write(to: source)
    try FTPBrowser.upload(connection: site, localURL: source, to: "/exception.txt")
    let destination = root.appendingPathComponent("download.txt")
    try FTPBrowser.download(connection: site, remotePath: "/exception.txt", isDirectory: false, to: destination)
    check(try Data(contentsOf: source) == Data(contentsOf: destination))
    try FTPBrowser.rename(connection: site, from: "/exception.txt", to: "/renamed.txt")
    check(prompts == before + 1)
    NativeFTPTransport.testPinOverride = "sha256//" + Data(repeating: 0, count: 32).base64EncodedString()
    defer { NativeFTPTransport.testPinOverride = nil }
    do {
        _ = try NativeFTPTransport.perform(connection: site, url: "ftp://127.0.0.1:21212/", operation: 0)
        preconditionFailure("Native transport accepted a wrong public-key pin")
    } catch { check((error as NSError).code == 90) }
    print("PASS: real local FTPS approval/retry, protocol 0 TLS, listing/upload/download/rename, wrong key rejected by native libcurl")
}
