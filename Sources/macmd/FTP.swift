import AppKit
import Foundation
import Security
import CryptoKit

struct FTPConnection: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var initialPath: String
    var comments: String
    var protocolType: Int
    var logonType: Int
    var passiveMode: String
    var encodingType: String
    var account: String
    var privateKeyPath: String
    var credentialAccessError: String? = nil
    var fileZillaXML: String? = nil
    var fileZillaFolders: [String]? = nil
    var certificatePath: String

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 21,
        username: String,
        password: String,
        initialPath: String = "/",
        comments: String = "",
        protocolType: Int = 0,
        logonType: Int = 1,
        passiveMode: String = "MODE_DEFAULT",
        encodingType: String = "Auto",
        account: String = "",
        privateKeyPath: String = "",
        certificatePath: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.initialPath = initialPath.isEmpty ? "/" : initialPath
        self.comments = comments
        self.protocolType = protocolType
        self.logonType = logonType
        self.passiveMode = passiveMode
        self.encodingType = encodingType
        self.account = account
        self.privateKeyPath = privateKeyPath
        self.certificatePath = certificatePath
    }

    var needsPasswordPrompt: Bool {
        logonType != 0 && (password.isEmpty || [2, 3].contains(logonType))
    }

    var displayName: String {
        name.isEmpty ? host : name
    }

    var resolvedName: String {
        displayName.isEmpty ? host : displayName
    }

    var scheme: String {
        switch protocolType {
        case 1:
            return "sftp"
        case 3:
            return "ftps"
        default:
            return "ftp"
        }
    }

    var protocolLabel: String {
        switch protocolType {
        case 0:
            return "FTP"
        case 1:
            return "SFTP"
        case 4:
            return "FTPS (Explicit)"
        case 3:
            return "FTPS (Implicit)"
        default:
            return "FTP"
        }
    }

    enum CodingKeys: String, CodingKey {
        case fileZillaXML, fileZillaFolders
        case id
        case name
        case host
        case port
        case username
        case password
        case initialPath
        case comments
        case protocolType
        case logonType
        case passiveMode
        case encodingType
        case account
        case privateKeyPath
        case certificatePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileZillaXML = try container.decodeIfPresent(String.self, forKey: .fileZillaXML)
        fileZillaFolders = try container.decodeIfPresent([String].self, forKey: .fileZillaFolders)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 21
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        initialPath = try container.decodeIfPresent(String.self, forKey: .initialPath) ?? "/"
        comments = try container.decodeIfPresent(String.self, forKey: .comments) ?? ""
        protocolType = try container.decodeIfPresent(Int.self, forKey: .protocolType) ?? 0
        logonType = try container.decodeIfPresent(Int.self, forKey: .logonType) ?? 0
        passiveMode = try container.decodeIfPresent(String.self, forKey: .passiveMode) ?? "MODE_DEFAULT"
        encodingType = try container.decodeIfPresent(String.self, forKey: .encodingType) ?? "Auto"
        account = try container.decodeIfPresent(String.self, forKey: .account) ?? ""
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        certificatePath = try container.decodeIfPresent(String.self, forKey: .certificatePath) ?? ""
    }
}

final class FTPConnectionStore {
    static let shared = FTPConnectionStore()
    private let key = "macmd.ftp.connections"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private(set) var lastError: Error?

    private func metadata() -> [FTPConnection] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FTPConnection].self, from: data) else { return [] }
        return decoded
    }

    private func hydrate(_ stored: FTPConnection, vault: [String: RemoteCredentials.Entry]) throws -> FTPConnection {
        var connection = stored
        if let entry = try vault[stored.id.uuidString] ?? RemoteCredentials.legacyEntry(stored.id) {
            connection.password = entry.password
            connection.fileZillaXML = entry.originalXML
        }
        return connection
    }

    func connections() -> [FTPConnection] {
        let profiles = metadata()
        guard !profiles.isEmpty else { return [] }
        do {
            let vault = try RemoteCredentials.vault()
            return profiles.map { stored in
                do { return try hydrate(stored, vault: vault) }
                catch {
                    var blocked = stored
                    blocked.credentialAccessError = error.localizedDescription
                    return blocked
                }
            }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            return profiles.map { stored in
                var blocked = stored
                blocked.credentialAccessError = error.localizedDescription
                return blocked
            }
        }
    }

    @discardableResult
    func save(_ connections: [FTPConnection]) -> Bool {
        do {
            if let blocked = connections.first(where: { $0.credentialAccessError != nil }) {
                throw RemoteTrust.error(blocked.credentialAccessError! + " Reimport the affected accounts from FileZilla XML to restore their credentials.")
            }
            let entries = Dictionary(uniqueKeysWithValues: connections.map {
                ($0.id.uuidString, RemoteCredentials.Entry(password: $0.password, originalXML: $0.fileZillaXML))
            })
            let profiles = connections.map { source -> FTPConnection in
                var stored = source
                stored.password = ""
                stored.fileZillaXML = nil
                return stored
            }
            let data = try JSONEncoder().encode(profiles)
            try RemoteCredentials.saveVault(entries)
            defaults.set(data, forKey: key)
            lastError = nil
            return true
        } catch { lastError = error; return false }
    }

    private func matches(_ lhs: FTPConnection, _ rhs: FTPConnection) -> Bool {
        lhs.id == rhs.id || (lhs.host.caseInsensitiveCompare(rhs.host) == .orderedSame &&
            lhs.port == rhs.port && lhs.protocolType == rhs.protocolType &&
            lhs.username == rhs.username && lhs.name == rhs.name && lhs.fileZillaFolders == rhs.fileZillaFolders)
    }

    @discardableResult
    func upsert(_ connection: FTPConnection) -> Bool { importConnections([connection]) }

    @discardableResult
    func importConnections(_ imported: [FTPConnection]) -> Bool {
        // Import replaces credentials from XML before any old per-account Keychain reads.
        var all = metadata()
        let replaced = Set(all.filter { stored in imported.contains(where: { matches(stored, $0) }) }.map(\.id))
        do {
            let vault = try RemoteCredentials.vault()
            all = try all.map { replaced.contains($0.id) ? $0 : try hydrate($0, vault: vault) }
        } catch { lastError = error; return false }
        for connection in imported {
            if let index = all.firstIndex(where: { matches($0, connection) }) {
                var updated = connection
                updated.id = all[index].id
                all[index] = updated
            } else { all.append(connection) }
        }
        guard save(all) else { return false }
        let restored = connections()
        // A successful XML import must include credentials that can actually be read back.
        return imported.allSatisfy { expected in
            restored.contains { matches($0, expected) && $0.password == expected.password }
        }
    }

    func remove(id: UUID) {
        save(connections().filter { $0.id != id })
    }
}

enum FTPBrowser {
    static func list(connection: FTPConnection, path: String) throws -> [FileItem] {
        try validate(path)
        let output = try runList(connection: connection, path: path)
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\r", with: "") }
            .filter { !$0.isEmpty }
        var items: [FileItem] = []
        if normalized(path) != "/" {
            items.append(FileItem(name: "..", url: makeURL(connection: connection, path: parentPath(of: path)), isDirectory: true, typeDescription: "", size: 0, modDate: .now, isParent: true, isVirtual: true))
        }

        for line in lines {
            guard let item = parseListLine(line, connection: connection, currentPath: path) else { continue }
            items.append(item)
        }
        return items
    }

    static func createDirectory(connection: FTPConnection, parentPath: String, name: String) throws {
        try validate(name)
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { throw RemoteTrust.error("Invalid folder name.") }
        let remotePath = childPath(parent: parentPath, child: name)
        try ensureRemoteDirectory(connection: connection, path: remotePath)
    }

    static func chmod(connection: FTPConnection, path: String, mode: String) throws {
        try validate(path)
        guard mode.count == 3 || mode.count == 4, mode.allSatisfy({ "01234567".contains($0) }) else { throw RemoteTrust.error("Enter an octal mode, for example 644 or 755.") }
        if connection.protocolType == 1 {
            _ = try runSFTPCommands(connection: connection, commands: [#"chmod \#(mode) "\#(escapeSFTP(path))""#])
        } else {
            _ = try runFTPCommands(connection: connection, basePath: parentPath(of: path), commands: ["SITE CHMOD \(mode) \(path)"])
        }
    }

    static func rename(connection: FTPConnection, from sourcePath: String, to destinationPath: String) throws {
        try validate(sourcePath); try validate(destinationPath)
        if sourcePath == destinationPath { throw RemoteTrust.error("Source and destination are identical.") }
        if connection.protocolType == 1 {
            _ = try runSFTPCommands(connection: connection, commands: [
                #"rename "\#(escapeSFTP(sourcePath))" "\#(escapeSFTP(destinationPath))""#
            ])
            return
        }

        _ = try runFTPCommands(connection: connection, basePath: parentPath(of: sourcePath), commands: [
            "RNFR \(sourcePath)",
            "RNTO \(destinationPath)"
        ])
    }

    static func delete(connection: FTPConnection, items: [FileItem], basePath: String) throws {
        for item in items where !item.isParent {
            let remotePath = childPath(parent: basePath, child: item.name)
            try delete(connection: connection, remotePath: remotePath, isDirectory: item.isDirectory)
        }
    }

    static func upload(connection: FTPConnection, localURL: URL, to remotePath: String, allowTrustPrompt: Bool = true) throws {
        try RemoteTransferControl.check()
        try validate(remotePath)
        let values = try localURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw RemoteTrust.error("Upload symbolic links as regular files explicitly; recursive link traversal is disabled.") }
        if values.isDirectory == true {
            try ensureRemoteDirectory(connection: connection, path: remotePath)
            let contents = try FileManager.default.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            for child in contents {
                let childRemotePath = childPath(parent: remotePath, child: child.lastPathComponent)
                try upload(connection: connection, localURL: child, to: childRemotePath)
            }
            return
        }

        let finalPath = remotePath
        let remotePath = childPath(parent: parentPath(of: finalPath), child: ".macmd-upload-\(UUID().uuidString)")
        var committed = false
        defer { if !committed { try? delete(connection: connection, remotePath: remotePath, isDirectory: false) } }
        if connection.protocolType == 1 {
            try ensureRemoteDirectory(connection: connection, path: parentPath(of: remotePath))
            _ = try runSFTPCommands(connection: connection, commands: [
                #"put "\#(escapeSFTP(localURL.path))" "\#(escapeSFTP(remotePath))""#
            ])
            try rename(connection: connection, from: remotePath, to: finalPath)
            committed = true
            return
        }

        // libcurl post-transfer commands reuse the authenticated TLS connection. It runs
        // these only after a successful upload, keeping the final file atomic.
        for attempt in 0..<3 {
            RemoteTransferControl.report("Nahrávam \(localURL.lastPathComponent) (pokus \(attempt + 1)/3)…")
            do {
                _ = try runNative(connection: connection, path: remotePath, operation: 2, localPath: localURL.path,
                                  commands: ["RNFR \(remotePath)", "RNTO \(finalPath)"], allowTrustPrompt: allowTrustPrompt)
            } catch {
                try RemoteTransferControl.check()
                let status = Int32((error as NSError).code)
                let detail = error.localizedDescription
                if status == 18 && detail.contains("426"),
                   try recoverCompletedUpload(connection: connection, source: localURL, stagingPath: remotePath, finalPath: finalPath) {
                    committed = true
                    return
                }
                if attempt < 2 && retryableUploadFailure(status: status, detail: detail) {
                    for _ in 0..<(attempt + 1) * 3 {
                        try RemoteTransferControl.check()
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    continue
                }
                throw error
            }
            committed = true
            return
        }
    }

    // Some FTPS servers reject the data-channel TLS shutdown even after receiving
    // all bytes. Only publish such an upload after independently reading it back
    // and verifying every byte via SHA-256. A matching size alone is insufficient.
    private static func recoverCompletedUpload(connection: FTPConnection, source: URL, stagingPath: String, finalPath: String) throws -> Bool {
        RemoteTransferControl.report("Overujem dokončenie uploadu…")
        let verification = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-verify-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: verification) }
        do {
            try download(connection: connection, remotePath: stagingPath, isDirectory: false, to: verification)
            guard try fileDigest(source) == fileDigest(verification) else { return false }
        } catch {
            try RemoteTransferControl.check()
            return false
        }
        try RemoteTransferControl.check()
        try rename(connection: connection, from: stagingPath, to: finalPath)
        return true
    }

    private static func fileDigest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try RemoteTransferControl.check()
            hash.update(data: data)
        }
        return hash.finalize()
    }

    static func retryableUploadFailure(status: Int32, detail: String) -> Bool {
        [7, 18, 28, 55, 56].contains(status) || (status == 19 && detail.contains("425"))
    }

    static func download(connection: FTPConnection, remotePath: String, isDirectory: Bool, to localURL: URL, allowTrustPrompt: Bool = true) throws {
        try validate(remotePath)
        let localValues = try? localURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if localValues?.isSymbolicLink == true { throw RemoteTrust.error("Refusing to overwrite a local symbolic link.") }
        if let directory = localValues?.isDirectory, directory != isDirectory { throw RemoteTrust.error("Destination has a different file type.") }
        if isDirectory {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            let children = try list(connection: connection, path: remotePath).filter { !$0.isParent }
            for child in children {
                let childRemotePath = childPath(parent: remotePath, child: child.name)
                let childLocalURL = localURL.appendingPathComponent(child.name)
                try download(connection: connection, remotePath: childRemotePath, isDirectory: child.isDirectory, to: childLocalURL)
            }
            return
        }

        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = localURL.deletingLastPathComponent().appendingPathComponent(".macmd-transfer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        if connection.protocolType == 1 {
            try runSFTPDownload(connection: connection, remotePath: remotePath, localPath: staging.path)
            try commitDownload(staging, to: localURL)
            return
        }

        _ = try runNative(connection: connection, path: remotePath, operation: 1, localPath: staging.path, allowTrustPrompt: allowTrustPrompt)
        try commitDownload(staging, to: localURL)
    }

    static func relayCopy(connection: FTPConnection, remotePath: String, isDirectory: Bool, to targetConnection: FTPConnection, targetDirectoryPath: String) throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-remote-copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let tempURL = tempRoot.appendingPathComponent(URL(fileURLWithPath: remotePath).lastPathComponent)
        try download(connection: connection, remotePath: remotePath, isDirectory: isDirectory, to: tempURL)
        let remoteTarget = childPath(parent: targetDirectoryPath, child: tempURL.lastPathComponent)
        try upload(connection: targetConnection, localURL: tempURL, to: remoteTarget)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    static func download(connection: FTPConnection, remotePath: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macmd-ftp-\(UUID().uuidString)-\(URL(fileURLWithPath: remotePath).lastPathComponent)")

        try download(connection: connection, remotePath: remotePath, isDirectory: false, to: tempURL)
        return tempURL
    }

    static func childPath(parent: String, child: String) -> String {
        let base = normalized(parent)
        if base == "/" { return "/\(child)" }
        return "\(base)/\(child)"
    }

    static func parentPath(of path: String) -> String {
        let normalizedPath = normalized(path)
        guard normalizedPath != "/" else { return "/" }
        let parent = URL(fileURLWithPath: normalizedPath).deletingLastPathComponent().path
        return parent.isEmpty ? "/" : parent
    }

    private static func parseListLine(_ line: String, connection: FTPConnection, currentPath: String) -> FileItem? {
        guard !line.hasPrefix("spawn "),
              !line.hasPrefix("Connected to "),
              !line.hasPrefix("sftp>"),
              !line.hasPrefix("Warning:"),
              !line.hasPrefix("** ") else { return nil }

        let pattern = #"^([\-ld])([rwxstST\-]{9})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(?:[A-Z][a-z]{2}\s+\d+|\d+\s+[A-Z][a-z]{2})\s+(?:\d{4}|\d{2}:\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let typeRange = Range(match.range(at: 1), in: line),
              let sizeRange = Range(match.range(at: 3), in: line),
              let nameRange = Range(match.range(at: 4), in: line) else {
            return nil
        }

        let typeChar = String(line[typeRange])
        let isDirectory = typeChar == "d"
        let size = Int64(line[sizeRange]) ?? 0
        let rawName = String(line[nameRange])
        let name = typeChar == "l" ? (rawName.components(separatedBy: " -> ").first ?? rawName) : rawName
        guard name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { return nil }
        let remotePath = childPath(parent: currentPath, child: name)
        return FileItem(
            name: name,
            url: makeURL(connection: connection, path: remotePath),
            isDirectory: isDirectory,
            typeDescription: isDirectory ? "Folder" : "File",
            size: size,
            modDate: .now,
            isParent: false,
            isVirtual: true
        )
    }

    private static func runList(connection: FTPConnection, path: String) throws -> String {
        if connection.protocolType == 1 {
            return try runSFTPList(connection: connection, path: path)
        }
        return try runFTPList(connection: connection, path: path, download: false)
    }

    private static func runFTPList(connection: FTPConnection, path: String, download: Bool, allowTrustPrompt: Bool = true) throws -> String {
        try runNative(connection: connection, path: path, operation: download ? 1 : 0, allowTrustPrompt: allowTrustPrompt)
    }

    private static func runNative(connection: FTPConnection, path: String, operation: Int32, localPath: String = "", commands: [String] = [], allowTrustPrompt: Bool = true) throws -> String {
        let url = remoteURLString(connection: connection, path: path, directory: operation == 0 || operation == 3)
        do {
            return try NativeFTPTransport.perform(connection: connection, url: url, operation: operation, localPath: localPath, commands: commands)
        } catch {
            guard allowTrustPrompt, [60, 90].contains((error as NSError).code), [0, 3, 4].contains(connection.protocolType) else { throw error }
            try RemoteTrust.trustCertificate(connection)
            return try NativeFTPTransport.perform(connection: connection, url: url, operation: operation, localPath: localPath, commands: commands)
        }
    }

    private static func runSFTPList(connection: FTPConnection, path: String) throws -> String {
        try runSFTPCommands(connection: connection, commands: [#"ls -la "\#(escapeSFTP(path))""#])
    }

    private static func runSFTPDownload(connection: FTPConnection, remotePath: String, localPath: String) throws {
        _ = try runSFTPCommands(connection: connection, commands: [#"get "\#(escapeSFTP(remotePath))" "\#(escapeSFTP(localPath))""#])
    }

    private static func delete(connection: FTPConnection, remotePath: String, isDirectory: Bool) throws {
        try validate(remotePath)
        guard normalized(remotePath) != "/" else { throw RemoteTrust.error("Cannot delete the remote root.") }
        if isDirectory {
            let children = try list(connection: connection, path: remotePath).filter { !$0.isParent }
            for child in children {
                let childPath = childPath(parent: remotePath, child: child.name)
                try delete(connection: connection, remotePath: childPath, isDirectory: child.isDirectory)
            }
            if connection.protocolType == 1 {
                _ = try runSFTPCommands(connection: connection, commands: [
                    #"rmdir "\#(escapeSFTP(remotePath))""#
                ])
            } else {
                _ = try runFTPCommands(connection: connection, basePath: parentPath(of: remotePath), commands: [
                    "RMD \(remotePath)"
                ])
            }
            return
        }

        if connection.protocolType == 1 {
            _ = try runSFTPCommands(connection: connection, commands: [
                #"rm "\#(escapeSFTP(remotePath))""#
            ])
        } else {
            _ = try runFTPCommands(connection: connection, basePath: parentPath(of: remotePath), commands: [
                "DELE \(remotePath)"
            ])
        }
    }

    private static func ensureRemoteDirectory(connection: FTPConnection, path: String) throws {
        try validate(path)
        let normalizedPath = normalized(path)
        guard normalizedPath != "/" else { return }
        let components = URL(fileURLWithPath: normalizedPath).pathComponents.filter { $0 != "/" }
        var current = "/"
        for component in components {
            current = childPath(parent: current, child: component)
            if connection.protocolType == 1 {
                _ = try? runSFTPCommands(connection: connection, commands: [
                    #"mkdir "\#(escapeSFTP(current))""#
                ])
            } else {
                _ = try? runFTPCommands(connection: connection, basePath: parentPath(of: current), commands: [
                    "MKD \(current)"
                ])
            }
        }
        _ = try list(connection: connection, path: normalizedPath)
    }

    private static func runSFTPCommands(connection: FTPConnection, commands: [String]) throws -> String {
        try runExpect(connection: connection, batchCommands: commands.joined(separator: "\n"))
    }

    private static func runFTPCommands(connection: FTPConnection, basePath: String, commands: [String], allowTrustPrompt: Bool = true) throws -> String {
        try runNative(connection: connection, path: basePath, operation: 3, commands: commands, allowTrustPrompt: allowTrustPrompt)
    }

    private static func runExpect(connection: FTPConnection, batchCommands: String) throws -> String {
        try RemoteTrust.checkSSH(connection)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-sftp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempDir.path)
        let askpass = tempDir.appendingPathComponent("askpass")
        try "#!/bin/sh\nprintf '%s\\n' \"$MACMD_REMOTE_PASSWORD\"\n".write(to: askpass, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
        let batchURL = tempDir.appendingPathComponent("commands.txt")
        try batchCommands.write(to: batchURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = ["-oBatchMode=no", "-oStrictHostKeyChecking=yes",
            "-oUserKnownHostsFile=\"\(RemoteTrust.knownHosts.path)\"", "-oConnectTimeout=20",
            "-oServerAliveInterval=15", "-oServerAliveCountMax=3", "-oNumberOfPasswordPrompts=1",
            "-b", batchURL.path, "-P", String(connection.port)]
        if !connection.privateKeyPath.isEmpty { process.arguments! += ["-i", connection.privateKeyPath] }
        process.arguments! += ["--", "\(connection.username)@\(connection.host)"]
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["SSH_ASKPASS"] = askpass.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = ":0"
        environment["MACMD_REMOTE_PASSWORD"] = connection.password
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let monitor = try RemoteTransferControl.start(process)
        defer { monitor?.cancel() }
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = ""
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: tempDir)

        try RemoteTransferControl.check()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "macmd.sftp", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr
            ])
        }
        return stdout + (stderr.isEmpty ? "" : "\n" + stderr)
    }

    private static func escapeSFTP(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
    }

    private static func remoteURLString(connection: FTPConnection, path: String, directory: Bool) -> String {
        var components = URLComponents()
        components.scheme = connection.scheme
        components.host = connection.host
        components.port = connection.port
        components.path = normalized(path) + (directory && !path.hasSuffix("/") ? "/" : "")
        return components.url!.absoluteString
    }

    private static func makeURL(connection: FTPConnection, path: String) -> URL {
        var components = URLComponents()
        components.scheme = connection.scheme
        components.host = connection.host
        components.port = connection.port
        components.user = connection.username
        components.path = normalized(path)
        return components.url ?? URL(fileURLWithPath: normalized(path))
    }

    private static func commitDownload(_ staging: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: destination) }
    }

    private static func validate(_ path: String) throws {
        try RemoteTransferControl.check()
        guard !path.contains("\r"), !path.contains("\n"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
            throw RemoteTrust.error("Unsupported path: control characters or parent traversal.")
        }
    }

    private static func normalized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }
}

/// The progress sheet supplies cancellation only for its worker thread.
enum RemoteTransferControl {
    static func report(_ message: String) {
        (Thread.current.threadDictionary["macmd.remote.progress"] as? (String) -> Void)?(message)
    }
    static func check() throws {
        if let cancelled = Thread.current.threadDictionary["macmd.remote.cancel"] as? () -> Bool, cancelled() {
            throw RemoteTrust.error("Transfer cancelled.")
        }
    }
    static func start(_ process: Process) throws -> DispatchSourceTimer? {
        try check()
        try process.run()
        guard let cancelled = Thread.current.threadDictionary["macmd.remote.cancel"] as? () -> Bool else { return nil }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        timer.setEventHandler { if cancelled(), process.isRunning { process.terminate() } }
        timer.resume()
        return timer
    }
}
