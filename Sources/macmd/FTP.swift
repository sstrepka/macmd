import AppKit
import Foundation

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
        logonType: Int = 0,
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
        case 4:
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
        case 3:
            return "FTPS (Explicit)"
        case 4:
            return "FTPS (Implicit)"
        default:
            return "FTP"
        }
    }

    enum CodingKeys: String, CodingKey {
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

    func connections() -> [FTPConnection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FTPConnection].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func save(_ connections: [FTPConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func upsert(_ connection: FTPConnection) {
        var all = connections()
        if let index = all.firstIndex(where: { $0.id == connection.id }) {
            all[index] = connection
        } else if let index = all.firstIndex(where: {
            $0.host.caseInsensitiveCompare(connection.host) == .orderedSame &&
            $0.port == connection.port &&
            $0.protocolType == connection.protocolType &&
            $0.username.caseInsensitiveCompare(connection.username) == .orderedSame
        }) {
            var updated = connection
            updated.id = all[index].id
            all[index] = updated
        } else {
            all.append(connection)
        }
        save(all)
    }

    func remove(id: UUID) {
        save(connections().filter { $0.id != id })
    }
}

enum FTPBrowser {
    static func list(connection: FTPConnection, path: String) throws -> [FileItem] {
        let output = try runList(connection: connection, path: path)
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) }
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
        let remotePath = childPath(parent: parentPath, child: name)
        try ensureRemoteDirectory(connection: connection, path: remotePath)
    }

    static func rename(connection: FTPConnection, from sourcePath: String, to destinationPath: String) throws {
        if connection.protocolType == 1 {
            _ = try runSFTPCommands(connection: connection, commands: [
                #"rename "\#(escapeSFTP(sourcePath))" "\#(escapeSFTP(destinationPath))""#
            ])
            return
        }

        _ = try runCurlCommands(connection: connection, basePath: parentPath(of: sourcePath), commands: [
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

    static func upload(connection: FTPConnection, localURL: URL, to remotePath: String) throws {
        let values = try localURL.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            try ensureRemoteDirectory(connection: connection, path: remotePath)
            let contents = try FileManager.default.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            for child in contents {
                let childRemotePath = childPath(parent: remotePath, child: child.lastPathComponent)
                try upload(connection: connection, localURL: child, to: childRemotePath)
            }
            return
        }

        if connection.protocolType == 1 {
            try ensureRemoteDirectory(connection: connection, path: parentPath(of: remotePath))
            _ = try runSFTPCommands(connection: connection, commands: [
                #"put "\#(escapeSFTP(localURL.path))" "\#(escapeSFTP(remotePath))""#
            ])
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--silent", "--show-error", "--ftp-create-dirs", "--user", "\(connection.username):\(connection.password)"]
            + protocolOptions(connection: connection)
            + ["--upload-file", localURL.path, remoteURLString(connection: connection, path: remotePath, directory: false)]
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "FTP upload failed"
            throw NSError(domain: "macmd.ftp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr])
        }
    }

    static func download(connection: FTPConnection, remotePath: String, isDirectory: Bool, to localURL: URL) throws {
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
        if connection.protocolType == 1 {
            try runSFTPDownload(connection: connection, remotePath: remotePath, localPath: localURL.path)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = curlArguments(connection: connection, path: remotePath, download: true, outputPath: localURL.path)
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "FTP download failed"
            throw NSError(domain: "macmd.ftp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr])
        }
    }

    static func relayCopy(connection: FTPConnection, remotePath: String, isDirectory: Bool, to targetConnection: FTPConnection, targetDirectoryPath: String) throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-remote-copy-\(UUID().uuidString)")
        let tempURL = tempRoot.appendingPathComponent(URL(fileURLWithPath: remotePath).lastPathComponent)
        try download(connection: connection, remotePath: remotePath, isDirectory: isDirectory, to: tempURL)
        let remoteTarget = childPath(parent: targetDirectoryPath, child: tempURL.lastPathComponent)
        try upload(connection: targetConnection, localURL: tempURL, to: remoteTarget)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    static func download(connection: FTPConnection, remotePath: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macmd-ftp-\(UUID().uuidString)-\(URL(fileURLWithPath: remotePath).lastPathComponent)")

        if connection.protocolType == 1 {
            try runSFTPDownload(connection: connection, remotePath: remotePath, localPath: tempURL.path)
            return tempURL
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = curlArguments(connection: connection, path: remotePath, download: true, outputPath: tempURL.path)
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "FTP download failed"
            throw NSError(domain: "macmd.ftp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr])
        }
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

        let pattern = #"^([\-ld])([rwx\-]{9})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+[A-Z][a-z]{2}\s+\d+\s+(?:\d{4}|\d{2}:\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let typeRange = Range(match.range(at: 1), in: line),
              let sizeRange = Range(match.range(at: 3), in: line),
              let nameRange = Range(match.range(at: 4), in: line) else {
            return nil
        }

        let typeChar = String(line[typeRange])
        let isDirectory = typeChar == "d" || typeChar == "l"
        let size = Int64(line[sizeRange]) ?? 0
        let name = String(line[nameRange])
        guard name != ".", name != ".." else { return nil }
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
        return try runCurl(connection: connection, path: path, download: false)
    }

    private static func runCurl(connection: FTPConnection, path: String, download: Bool) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = curlArguments(connection: connection, path: path, download: download, outputPath: nil)
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "macmd.ftp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr])
        }
        return stdout
    }

    private static func runSFTPList(connection: FTPConnection, path: String) throws -> String {
        let script = """
        set timeout 20
        set password [lindex $argv 0]
        set destination [lindex $argv 1]
        set commandfile [lindex $argv 2]
        set keyfile [lindex $argv 3]
        set port [lindex $argv 4]
        proc run_commands {commandfile} {
            set fh [open $commandfile r]
            set commands [read $fh]
            close $fh
            foreach line [split $commands "\\n"] {
                if {$line ne ""} {
                    if {[catch {send -- "$line\\r"}]} { return }
                    expect {
                        -re "sftp> $" {}
                        eof { return }
                        timeout { return }
                    }
                }
            }
            catch {send -- "quit\\r"}
            expect {
                eof {}
                timeout {}
            }
        }
        if {$keyfile ne ""} {
            spawn /usr/bin/sftp -oStrictHostKeyChecking=accept-new -oPubkeyAuthentication=yes -oPasswordAuthentication=yes -i $keyfile -P $port $destination
        } else {
            spawn /usr/bin/sftp -oStrictHostKeyChecking=accept-new -oPubkeyAuthentication=yes -oPasswordAuthentication=yes -P $port $destination
        }
        expect {
            -re ".*yes/no.*" { send "yes\\r"; exp_continue }
            -re ".*assword:.*" { send "$password\\r"; exp_continue }
            -re "sftp> $" { run_commands $commandfile }
            eof
        }
        catch wait result
        set code [lindex $result 3]
        exit $code
        """

        let batch = """
        cd "\(escapeSFTP(path))"
        ls -la
        quit
        """
        return try runExpect(connection: connection, script: script, batchCommands: batch)
    }

    private static func runSFTPDownload(connection: FTPConnection, remotePath: String, localPath: String) throws {
        let parent = parentPath(of: remotePath)
        let fileName = URL(fileURLWithPath: remotePath).lastPathComponent
        let batch = """
        cd "\(escapeSFTP(parent))"
        get "\(escapeSFTP(fileName))" "\(escapeSFTP(localPath))"
        """
        let script = """
        set timeout 30
        set password [lindex $argv 0]
        set destination [lindex $argv 1]
        set commandfile [lindex $argv 2]
        set keyfile [lindex $argv 3]
        set port [lindex $argv 4]
        proc run_commands {commandfile} {
            set fh [open $commandfile r]
            set commands [read $fh]
            close $fh
            foreach line [split $commands "\\n"] {
                if {$line ne ""} {
                    if {[catch {send -- "$line\\r"}]} { return }
                    expect {
                        -re "sftp> $" {}
                        eof { return }
                        timeout { return }
                    }
                }
            }
            catch {send -- "quit\\r"}
            expect {
                eof {}
                timeout {}
            }
        }
        if {$keyfile ne ""} {
            spawn /usr/bin/sftp -oStrictHostKeyChecking=accept-new -oPubkeyAuthentication=yes -oPasswordAuthentication=yes -i $keyfile -P $port $destination
        } else {
            spawn /usr/bin/sftp -oStrictHostKeyChecking=accept-new -oPubkeyAuthentication=yes -oPasswordAuthentication=yes -P $port $destination
        }
        expect {
            -re ".*yes/no.*" { send "yes\\r"; exp_continue }
            -re ".*assword:.*" { send "$password\\r"; exp_continue }
            -re "sftp> $" { run_commands $commandfile }
            eof
        }
        catch wait result
        set code [lindex $result 3]
        exit $code
        """
        _ = try runExpect(connection: connection, script: script, batchCommands: batch)
    }

    private static func delete(connection: FTPConnection, remotePath: String, isDirectory: Bool) throws {
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
                _ = try runCurlCommands(connection: connection, basePath: parentPath(of: remotePath), commands: [
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
            _ = try runCurlCommands(connection: connection, basePath: parentPath(of: remotePath), commands: [
                "DELE \(remotePath)"
            ])
        }
    }

    private static func ensureRemoteDirectory(connection: FTPConnection, path: String) throws {
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
                _ = try? runCurlCommands(connection: connection, basePath: parentPath(of: current), commands: [
                    "MKD \(current)"
                ])
            }
        }
    }

    private static func runSFTPCommands(connection: FTPConnection, commands: [String]) throws -> String {
        try runExpect(connection: connection, script: sftpExpectScript(timeout: 60), batchCommands: commands.joined(separator: "\n"))
    }

    private static func sftpExpectScript(timeout: Int) -> String {
        """
        set timeout \(timeout)
        set password [lindex $argv 0]
        set destination [lindex $argv 1]
        set commandfile [lindex $argv 2]
        set keyfile [lindex $argv 3]
        set port [lindex $argv 4]
        proc run_commands {commandfile} {
            set fh [open $commandfile r]
            set commands [read $fh]
            close $fh
            foreach line [split $commands "\\n"] {
                if {$line ne ""} {
                    if {[catch {send -- "$line\\r"}]} { return }
                    expect {
                        -re "sftp> $" {}
                        eof { return }
                        timeout { return }
                    }
                }
            }
            catch {send -- "quit\\r"}
            expect {
                eof {}
                timeout {}
            }
        }
        if {$keyfile ne ""} {
            spawn /usr/bin/sftp -oStrictHostKeyChecking=accept-new -oPubkeyAuthentication=yes -oPasswordAuthentication=yes -i $keyfile -P $port $destination
        } else {
            spawn /usr/bin/sftp -oStrictHostKeyChecking=accept-new -oPubkeyAuthentication=yes -oPasswordAuthentication=yes -P $port $destination
        }
        expect {
            -re ".*yes/no.*" { send "yes\\r"; exp_continue }
            -re ".*assword:.*" { send "$password\\r"; exp_continue }
            -re "sftp> $" { run_commands $commandfile }
            eof
        }
        catch wait result
        set code [lindex $result 3]
        exit $code
        """
    }

    private static func runCurlCommands(connection: FTPConnection, basePath: String, commands: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--silent", "--show-error", "--user", "\(connection.username):\(connection.password)"]
            + protocolOptions(connection: connection)
            + commands.flatMap { ["-Q", $0] }
            + [remoteURLString(connection: connection, path: basePath, directory: true)]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "macmd.ftp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr])
        }
        return stdout
    }

    private static func runExpect(connection: FTPConnection, script: String, batchCommands: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-sftp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptURL = tempDir.appendingPathComponent("run.expect")
        let batchURL = tempDir.appendingPathComponent("commands.txt")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try batchCommands.write(to: batchURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
        process.arguments = [
            scriptURL.path,
            connection.password,
            "\(connection.username)@\(connection.host)",
            batchURL.path,
            connection.privateKeyPath,
            "\(connection.port)"
        ]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try? FileManager.default.removeItem(at: tempDir)

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "macmd.sftp", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr
            ])
        }
        return stdout + (stderr.isEmpty ? "" : "\n" + stderr)
    }

    private static func curlArguments(connection: FTPConnection, path: String, download: Bool, outputPath: String?) -> [String] {
        var args = ["--silent", "--show-error", "--user", "\(connection.username):\(connection.password)"]
        args += protocolOptions(connection: connection)
        if download {
            if let outputPath {
                args += ["--output", outputPath]
            }
        }
        args.append(remoteURLString(connection: connection, path: path, directory: !download))
        return args
    }

    private static func protocolOptions(connection: FTPConnection) -> [String] {
        var args: [String] = []
        switch connection.protocolType {
        case 0:
            if connection.passiveMode == "MODE_ACTIVE" {
                args += ["--ftp-port", "-"]
            } else {
                args += ["--ftp-pasv"]
            }
        case 1:
            if !connection.privateKeyPath.isEmpty {
                args += ["--key", connection.privateKeyPath]
            }
        case 3:
            args += ["--ssl-reqd"]
            if !connection.certificatePath.isEmpty {
                args += ["--cert", connection.certificatePath]
            }
        case 4:
            if !connection.certificatePath.isEmpty {
                args += ["--cert", connection.certificatePath]
            }
        default:
            break
        }
        return args
    }

    private static func escapeSFTP(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func remoteURLString(connection: FTPConnection, path: String, directory: Bool) -> String {
        let cleanPath = normalized(path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleanPath.isEmpty {
            return "\(connection.scheme)://\(connection.host):\(connection.port)/"
        }
        return directory
            ? "\(connection.scheme)://\(connection.host):\(connection.port)/\(cleanPath)/"
            : "\(connection.scheme)://\(connection.host):\(connection.port)/\(cleanPath)"
    }

    private static func makeURL(connection: FTPConnection, path: String) -> URL {
        var components = URLComponents()
        components.scheme = connection.scheme
        components.host = connection.host
        components.port = connection.port
        components.user = connection.username
        components.password = connection.password
        components.path = normalized(path)
        return components.url ?? URL(fileURLWithPath: normalized(path))
    }

    private static func normalized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }
}

enum FileZillaImport {
    static func loadConnections(from url: URL) throws -> [FTPConnection] {
        let xml = try String(contentsOf: url, encoding: .utf8)
        return serverBlocks(in: xml).compactMap(parseServerBlock(_:))
    }

    private static func serverBlocks(in xml: String) -> [String] {
        matches(for: #"<Server\b[^>]*>[\s\S]*?<\/Server>"#, in: xml)
    }

    private static func parseServerBlock(_ xml: String) -> FTPConnection? {
        let host = value("Host", in: xml)
        guard !host.isEmpty else { return nil }

        let protocolType = Int(value("Protocol", in: xml)) ?? 0
        let logonType = Int(value("Logontype", in: xml)) ?? 0
        let port = Int(value("Port", in: xml)) ?? 21
        let username = value("User", in: xml)
        let password = decodedPass(in: xml)
        let comments = value("Comments", in: xml)
        let passiveMode = value("PasvMode", in: xml)
        let encodingType = value("EncodingType", in: xml)
        let account = value("Account", in: xml)
        let privateKeyPath = value("Keyfile", in: xml)
        let certificatePath = value("Certificate", in: xml)
        let remoteDirRaw = value("RemoteDir", in: xml)
        let initialPath = decodeRemoteDir(remoteDirRaw)

        let name = value("Name", in: xml).ifEmpty(attribute("name", in: xml))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? host

        return FTPConnection(
            name: name.isEmpty ? host : name,
            host: host,
            port: port,
            username: username,
            password: password,
            initialPath: initialPath,
            comments: comments,
            protocolType: protocolType,
            logonType: logonType,
            passiveMode: passiveMode.isEmpty ? "MODE_DEFAULT" : passiveMode,
            encodingType: encodingType.isEmpty ? "Auto" : encodingType,
            account: account,
            privateKeyPath: privateKeyPath,
            certificatePath: certificatePath
        )
    }

    private static func value(_ childName: String, in xml: String) -> String {
        let pattern = #"<\#(childName)\b[^>]*>([\s\S]*?)<\/\#(childName)>"#
        guard let first = matches(for: pattern, in: xml).first else { return "" }
        return decodeEntities(first).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodedPass(in xml: String) -> String {
        let plain = value("Pass", in: xml)
        let attributes = tagAttributes("Pass", in: xml)
        if attributes["encoding"]?.lowercased() == "base64",
           let data = Data(base64Encoded: plain),
           let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return plain
    }

    private static func attribute(_ name: String, in xml: String) -> String? {
        let pattern = #"<Server\b[^>]*\#(name)="([^"]*)"[^>]*>"#
        return matches(for: pattern, in: xml).first.map(decodeEntities(_:))
    }

    private static func tagAttributes(_ tag: String, in xml: String) -> [String: String] {
        let pattern = #"<\#(tag)\b([^>]*)>"#
        guard let raw = matches(for: pattern, in: xml).first else { return [:] }
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z0-9_:\-]+)="([^"]*)""#, options: []) else { return [:] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var output: [String: String] = [:]
        for match in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: raw),
                  let valueRange = Range(match.range(at: 2), in: raw) else { continue }
            output[String(raw[keyRange])] = decodeEntities(String(raw[valueRange]))
        }
        return output
    }

    private static func matches(for pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            guard let outputRange = Range(match.range(at: captureIndex), in: string) else { return nil }
            return String(string[outputRange])
        }
    }

    private static func decodeEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func decodeRemoteDir(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        if trimmed.hasPrefix("/") {
            return trimmed
        }

        let tokens = trimmed.split(separator: " ").map(String.init)
        guard tokens.count >= 3, tokens.first == "1" else { return "/" }

        var parts: [String] = []
        var index = 2
        while index + 1 < tokens.count {
            let length = Int(tokens[index]) ?? 0
            let value = tokens[index + 1]
            if length > 0, value.count == length {
                parts.append(value)
            }
            index += 2
        }
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }
}

private extension String {
    func ifEmpty(_ fallback: @autoclosure () -> String?) -> String? {
        isEmpty ? fallback() : self
    }
}
