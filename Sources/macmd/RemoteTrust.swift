import AppKit
import Foundation

enum RemoteTrust {
    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("macmd/Trust")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }
    static var knownHosts: URL { directory.appendingPathComponent("known_hosts") }
    private static let lock = NSLock()

    static func run(_ executable: String, _ arguments: [String]) throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 25, execute: timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    static func approve(title: String, detail: String) -> Bool {
        var accepted = false
        let show = {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.addButton(withTitle: "Trust and Connect")
            alert.addButton(withTitle: "Cancel")
            accepted = alert.runModal() == .alertFirstButtonReturn
        }
        if Thread.isMainThread { show() } else { DispatchQueue.main.sync(execute: show) }
        return accepted
    }

    static func checkSSH(_ connection: FTPConnection) throws {
        lock.lock(); defer { lock.unlock() }
        let host = connection.port == 22 ? connection.host : "[\(connection.host)]:\(connection.port)"
        if FileManager.default.fileExists(atPath: knownHosts.path) {
            let result = try run("/usr/bin/ssh-keygen", ["-F", host, "-f", knownHosts.path])
            if result.0 == 0 { return } // OpenSSH rejects changed keys; never replace automatically.
        }
        let result = try run("/usr/bin/ssh-keyscan", ["-T", "10", "-p", String(connection.port), "--", connection.host])
        let text = String(decoding: result.1, as: UTF8.self)
        let keys = text.components(separatedBy: .newlines).filter { !$0.hasPrefix("#") && $0.split(separator: " ").count == 3 }.joined(separator: "\n") + "\n"
        guard result.0 == 0, keys != "\n" else { throw error("Could not obtain SSH host keys for \(host).") }
        let temp = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try keys.write(to: temp, atomically: true, encoding: .utf8)
        let fingerprints = try run("/usr/bin/ssh-keygen", ["-lf", temp.path, "-E", "sha256"])
        guard fingerprints.0 == 0, approve(title: "Trust SSH host keys?", detail: "\(host)\n\n\(String(decoding: fingerprints.1, as: UTF8.self))\nVerify these fingerprints with the server administrator. Changed keys will be rejected.") else { throw error("SSH host key was not trusted.") }
        let previous = (try? String(contentsOf: knownHosts, encoding: .utf8)) ?? ""
        try (previous + keys).write(to: knownHosts, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHosts.path)
    }

    static func certificate(for connection: FTPConnection) -> URL? {
        let name = Data("\(connection.host):\(connection.port)".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        let url = directory.appendingPathComponent(name + ".pem")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Called explicitly from the connection manager. curl still verifies hostname and certificate validity.
    static func trustCertificate(_ connection: FTPConnection) throws {
        var args = ["s_client", "-connect", "\(connection.host):\(connection.port)", "-servername", connection.host, "-showcerts"]
        if connection.protocolType == 4 { args += ["-starttls", "ftp"] }
        let result = try run("/usr/bin/openssl", args)
        let text = String(decoding: result.1, as: UTF8.self)
        guard let start = text.range(of: "-----BEGIN CERTIFICATE-----"), let end = text.range(of: "-----END CERTIFICATE-----") else { throw error("Server did not provide a TLS certificate.") }
        let pem = String(text[start.lowerBound..<end.upperBound]) + "\n"
        let temp = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try pem.write(to: temp, atomically: true, encoding: .utf8)
        let info = try run("/usr/bin/openssl", ["x509", "-in", temp.path, "-noout", "-subject", "-issuer", "-dates", "-fingerprint", "-sha256"])
        guard info.0 == 0, approve(title: "Trust TLS certificate?", detail: "\(connection.host):\(connection.port)\n\n\(String(decoding: info.1, as: UTF8.self))\nVerify this fingerprint with the server administrator.") else { throw error("TLS certificate was not trusted.") }
        let name = Data("\(connection.host):\(connection.port)".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        try pem.write(to: directory.appendingPathComponent(name + ".pem"), atomically: true, encoding: .utf8)
    }
    static func error(_ message: String) -> NSError { NSError(domain: "macmd.remote", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
