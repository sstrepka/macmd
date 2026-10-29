import AppKit
import Foundation
import CryptoKit

enum RemoteTrust {
    #if MACMD_TLS_TESTS
    static var testDirectory: URL?
    static var testCertificate: (() throws -> String)?
    static var testApproval: (() -> (Bool, Bool))?
    #endif
    static var directory: URL {
        #if MACMD_TLS_TESTS
        if let testDirectory { return testDirectory }
        #endif
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("macmd/Trust")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }
    static var knownHosts: URL { directory.appendingPathComponent("known_hosts") }
    private static let lock = NSLock()

    static func run(_ executable: String, _ arguments: [String], timeoutSeconds: TimeInterval = 25) throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
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

    private static var sessionCertificates: [String: String] = [:]

    private static func exceptionURL(_ connection: FTPConnection) -> URL {
        let key = "\(connection.protocolType):\(connection.host.lowercased()):\(connection.port)"
        return directory.appendingPathComponent(Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") + ".exception.pem")
    }

    static func forgetTLSException(_ connection: FTPConnection) throws {
        lock.lock(); defer { lock.unlock() }
        let url = exceptionURL(connection)
        sessionCertificates.removeValue(forKey: url.path)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private static func serverCertificate(_ connection: FTPConnection) throws -> String {
        guard [0, 3, 4].contains(connection.protocolType) else { throw error("Select a TLS FTP site first.") }
        #if MACMD_TLS_TESTS
        if let testCertificate { return try testCertificate() }
        #endif
        RemoteTransferControl.report("Overujem certifikát FTP servera…")
        var args = ["s_client", "-connect", "\(connection.host):\(connection.port)", "-servername", connection.host, "-showcerts"]
        if connection.protocolType != 3 { args += ["-starttls", "ftp"] }
        let result = try run("/usr/bin/openssl", args, timeoutSeconds: 10)
        let text = String(decoding: result.1, as: UTF8.self)
        guard let start = text.range(of: "-----BEGIN CERTIFICATE-----"), let end = text.range(of: "-----END CERTIFICATE-----"), start.lowerBound < end.upperBound else { throw error("Server did not provide a TLS certificate.") }
        return String(text[start.lowerBound..<end.upperBound]) + "\n"
    }

    /// Explicit exception, scoped to this host, port, protocol and exact certificate.
    static func trustCertificate(_ connection: FTPConnection) throws {
        lock.lock(); defer { lock.unlock() }
        try approveCertificate(connection, pem: serverCertificate(connection))
    }

    private static func approveCertificate(_ connection: FTPConnection, pem: String) throws {
        let temp = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try pem.write(to: temp, atomically: true, encoding: .utf8)
        let info = try run("/usr/bin/openssl", ["x509", "-in", temp.path, "-noout", "-subject", "-issuer", "-dates", "-fingerprint", "-sha256", "-text"])
        guard info.0 == 0 else { throw error("Could not read TLS certificate.") }
        let details = String(decoding: info.1, as: UTF8.self)
        let summary = details.components(separatedBy: "Certificate:").first ?? details
        let lines = details.components(separatedBy: .newlines)
        let names = lines.indices.filter { lines[$0].contains("Subject Alternative Name") }.map { $0 + 1 < lines.count ? lines[$0 + 1].trimmingCharacters(in: .whitespaces) : "" }.joined(separator: "\n")
        var accepted = false
        var remember = false
        let show = {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Trust this FTP server certificate?"
            alert.informativeText = "\(connection.host):\(connection.port)\n\nThe certificate could not be verified automatically, or an exception was requested. Its name, issuer or validity may not match.\n\n\(summary)\n\(names)\n\nVerify the SHA-256 fingerprint with your hosting provider before continuing. A changed certificate will require approval again."
            let checkbox = NSButton(checkboxWithTitle: "Always trust this certificate for this server", target: nil, action: nil)
            alert.accessoryView = checkbox
            alert.addButton(withTitle: "Trust and Connect")
            alert.addButton(withTitle: "Cancel")
            accepted = alert.runModal() == .alertFirstButtonReturn
            remember = checkbox.state == .on
        }
        #if MACMD_TLS_TESTS
        if let testApproval { (accepted, remember) = testApproval() }
        else if Thread.isMainThread { show() } else { DispatchQueue.main.sync(execute: show) }
        #else
        if Thread.isMainThread { show() } else { DispatchQueue.main.sync(execute: show) }
        #endif
        guard accepted else { throw error("TLS certificate was not trusted. No connection was authorized.") }
        let url = exceptionURL(connection)
        if remember {
            try pem.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        sessionCertificates[url.path] = pem
    }

    private final class TLSBatch {
        var options: [String: (String, [String])] = [:]
    }
    static func beginTLSBatch() { Thread.current.threadDictionary["macmd.tls.batch"] = TLSBatch() }
    static func endTLSBatch() { Thread.current.threadDictionary.removeObject(forKey: "macmd.tls.batch") }

    static func tlsExceptionOptions(_ connection: FTPConnection) throws -> [String] {
        guard [0, 3, 4].contains(connection.protocolType) else { return [] }
        lock.lock(); defer { lock.unlock() }
        let url = exceptionURL(connection)
        guard let saved = sessionCertificates[url.path] ?? (try? String(contentsOf: url, encoding: .utf8)) else { return [] }
        let batch = Thread.current.threadDictionary["macmd.tls.batch"] as? TLSBatch
        if let cached = batch?.options[url.path], cached.0 == saved { return cached.1 }
        let current = try serverCertificate(connection)
        if saved != current { try approveCertificate(connection, pem: current) }
        let temp = directory.appendingPathComponent(UUID().uuidString)
        let key = temp.appendingPathExtension("pub")
        defer { try? FileManager.default.removeItem(at: temp); try? FileManager.default.removeItem(at: key) }
        try current.write(to: temp, atomically: true, encoding: .utf8)
        let publicKey = try run("/usr/bin/openssl", ["x509", "-in", temp.path, "-pubkey", "-noout"])
        guard publicKey.0 == 0 else { throw error("Could not pin TLS public key.") }
        try publicKey.1.write(to: key)
        let der = try run("/usr/bin/openssl", ["pkey", "-pubin", "-in", key.path, "-outform", "DER"])
        guard der.0 == 0 else { throw error("Could not pin TLS public key.") }
        let pin = Data(SHA256.hash(data: der.1)).base64EncodedString()
        // Verification is replaced only for the approved certificate; curl enforces its key on the actual transfer.
        let options = ["--insecure", "--pinnedpubkey", "sha256//" + pin, "--ssl-reqd"]
        batch?.options[url.path] = (current, options)
        return options
    }
    static func error(_ message: String) -> NSError { NSError(domain: "macmd.remote", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
