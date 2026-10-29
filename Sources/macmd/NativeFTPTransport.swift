import Foundation
import CryptoKit
import CNativeFTP

/// libcurl owns FTP protocol state, persistent connections and TLS session reuse.
/// Swift owns profile credentials, explicit certificate approval and atomic paths.
enum NativeFTPTransport {
    private final class Session {
        let handle: OpaquePointer
        let lock = NSLock()
        var lastUsed = Date()
        init() throws {
            guard let handle = macmd_ftp_create() else { throw RemoteTrust.error("Could not initialize the FTP engine.") }
            self.handle = handle
        }
        deinit { macmd_ftp_destroy(handle) }
    }
    #if MACMD_TLS_TESTS
    static var testPinOverride: String?
    #endif
    private static let poolLock = NSLock()
    private static var sessions: [String: Session] = [:]
    static var version: String { String(cString: macmd_ftp_version()) }

    private static func session(for connection: FTPConnection) throws -> Session {
        let identity = [connection.id.uuidString, connection.host.lowercased(), String(connection.port), String(connection.protocolType), connection.username, connection.password, connection.account, connection.passiveMode, connection.certificatePath].joined(separator: "\0")
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        poolLock.lock(); defer { poolLock.unlock() }
        if let existing = sessions[key] { existing.lastUsed = Date(); return existing }
        let created = try Session()
        if sessions.count >= 8, let oldest = sessions.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key { sessions.removeValue(forKey: oldest) }
        sessions[key] = created
        return created
    }

    static func perform(connection: FTPConnection, url: String, operation: Int32, localPath: String = "", commands: [String] = []) throws -> String {
        try RemoteTransferControl.check()
        let exception = try RemoteTrust.tlsExceptionOptions(connection)
        var pin = exception.firstIndex(of: "--pinnedpubkey").map { exception[$0 + 1] } ?? ""
        #if MACMD_TLS_TESTS
        if let testPinOverride { pin = testPinOverride }
        #endif
        let ca = [3, 4].contains(connection.protocolType) ? RemoteTrust.certificate(for: connection)?.path ?? "" : ""
        let session = try session(for: connection)
        while !session.lock.try() {
            try RemoteTransferControl.check()
            Thread.sleep(forTimeInterval: 0.05)
        }
        defer { session.lock.unlock() }
        let values = [url, connection.username, connection.password, connection.account, pin, ca, connection.certificatePath, localPath, commands.joined(separator: "\n")]
        let strings = values.map { strdup($0)! }
        defer { strings.forEach { free($0) } }
        var request = macmd_ftp_request()
        request.url = UnsafePointer(strings[0]); request.username = UnsafePointer(strings[1])
        request.password = UnsafePointer(strings[2]); request.account = UnsafePointer(strings[3])
        request.pinned_key = UnsafePointer(strings[4]); request.ca_file = UnsafePointer(strings[5])
        request.client_certificate = UnsafePointer(strings[6]); request.local_path = UnsafePointer(strings[7])
        request.commands = UnsafePointer(strings[8]); request.protocol = Int32(connection.protocolType)
        request.active = connection.passiveMode == "MODE_ACTIVE" ? 1 : 0
        request.operation = operation
        var output: UnsafeMutablePointer<UInt8>?
        var size = 0
        var detail: UnsafeMutablePointer<CChar>?
        let status = macmd_ftp_perform(session.handle, &request, { _, _, _, _, _ in
            do { try RemoteTransferControl.check(); return 0 } catch { return 1 }
        }, nil, &output, &size, &detail)
        defer { macmd_ftp_free(output); macmd_ftp_free(detail) }
        try RemoteTransferControl.check()
        if status != 0 {
            let stage = ["Directory listing", "Download", "Upload", "FTP command"][Int(operation)]
            let trust = pin.isEmpty ? "system certificate verification" : "approved certificate + public-key pin"
            let message = detail.map { String(cString: $0) } ?? "FTP transfer failed."
            throw NSError(domain: "macmd.ftp", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "\(stage): \(connection.host):\(connection.port), protocol \(connection.protocolType), TLS: \(trust)\nEngine: \(version)\n\n\(message)"])
        }
        guard let output, size > 0 else { return "" }
        return String(decoding: UnsafeBufferPointer(start: output, count: size), as: UTF8.self)
    }
}
