import Foundation

/// Preserve the original Server subtree, including fields newer than this client.
enum FileZillaImport {
    static func loadConnections(from url: URL) throws -> [FTPConnection] {
        let document = try XMLDocument(contentsOf: url, options: [.nodePreserveAll])
        guard document.rootElement()?.name == "FileZilla3" else { throw failure("Expected a FileZilla3 XML export.") }
        return try document.nodes(forXPath: "//Servers//Server").compactMap { node in
            guard let server = node as? XMLElement else { return nil }
            func value(_ name: String) -> String { server.elements(forName: name).first?.stringValue ?? "" }
            let host = value("Host")
            guard !host.isEmpty else { return nil }
            let pass = server.elements(forName: "Pass").first
            let encoding = pass?.attribute(forName: "encoding")?.stringValue ?? ""
            let raw = pass?.stringValue ?? ""
            let password: String
            switch encoding {
            case "", "plain": password = raw
            case "base64":
                guard let data = Data(base64Encoded: raw), let text = String(data: data, encoding: .utf8) else {
                    throw failure("Invalid Base64 password for \(host).")
                }
                password = text
            case "crypt": password = "" // Preserve encrypted value for export; ask on connection.
            default: throw failure("Unsupported password encoding for \(host): \(encoding)")
            }
            let proto = Int(value("Protocol")) ?? 0
            var connection = FTPConnection(name: value("Name").isEmpty ? host : value("Name"), host: host,
                port: Int(value("Port")) ?? (proto == 1 ? 22 : proto == 3 ? 990 : 21),
                username: value("User"), password: password, initialPath: decodeRemoteDir(value("RemoteDir")),
                comments: value("Comments"), protocolType: proto, logonType: Int(value("Logontype")) ?? 1,
                passiveMode: value("PasvMode").isEmpty ? "MODE_DEFAULT" : value("PasvMode"),
                encodingType: value("EncodingType").isEmpty ? "Auto" : value("EncodingType"), account: value("Account"),
                privateKeyPath: value("Keyfile"), certificatePath: value("Certificate"))
            connection.fileZillaXML = server.xmlString
            var folders: [String] = []
            var parent = server.parent
            while let node = parent, node.name != "Servers" {
                if node.name == "Folder", let folder = node as? XMLElement {
                    // Folder name is direct text, not descendant Server text.
                    folders.insert(folder.children?.filter { $0.kind == .text }.compactMap(\.stringValue).joined().trimmingCharacters(in: .whitespacesAndNewlines) ?? "", at: 0)
                }
                parent = node.parent
            }
            connection.fileZillaFolders = folders
            return connection
        }
    }

    static func export(_ connections: [FTPConnection], to url: URL) throws {
        let root = XMLElement(name: "FileZilla3")
        root.addAttribute(XMLNode.attribute(withName: "version", stringValue: "3.0.0") as! XMLNode)
        let servers = XMLElement(name: "Servers")
        root.addChild(servers)
        for connection in connections where !connection.host.isEmpty {
            var parent = servers
            for name in connection.fileZillaFolders ?? [] {
                let existing = parent.elements(forName: "Folder").first { folder in
                    folder.children?.first(where: { $0.kind == .text })?.stringValue == name
                }
                let folder = existing ?? XMLElement(name: "Folder", stringValue: name)
                if existing == nil { parent.addChild(folder) }
                parent = folder
            }
            let server: XMLElement
            if let original = connection.fileZillaXML { server = try XMLElement(xmlString: original) }
            else { server = XMLElement(name: "Server") }
            func set(_ name: String, _ value: String) {
                for child in server.elements(forName: name) { child.detach() }
                server.addChild(XMLElement(name: name, stringValue: value))
            }
            set("Host", connection.host); set("Port", String(connection.port))
            set("Protocol", String(connection.protocolType)); set("User", connection.username)
            set("Logontype", String(connection.logonType)); set("Name", connection.name)
            set("Comments", connection.comments); set("PasvMode", connection.passiveMode)
            set("EncodingType", connection.encodingType); set("Account", connection.account)
            set("Keyfile", connection.privateKeyPath)
            if !connection.certificatePath.isEmpty { set("Certificate", connection.certificatePath) }
            // Retain exotic path types unchanged when the user has not edited their projection.
            let oldPath = server.elements(forName: "RemoteDir").first?.stringValue ?? ""
            if decodeRemoteDir(oldPath) != connection.initialPath || oldPath.isEmpty {
                set("RemoteDir", encodeRemoteDir(connection.initialPath))
            }
            let encrypted = server.elements(forName: "Pass").first?.attribute(forName: "encoding")?.stringValue == "crypt"
            if !encrypted || !connection.password.isEmpty {
                set("Pass", Data(connection.password.utf8).base64EncodedString())
                server.elements(forName: "Pass").first?.addAttribute(XMLNode.attribute(withName: "encoding", stringValue: "base64") as! XMLNode)
            }
            if server.elements(forName: "Type").isEmpty { set("Type", "0") }
            parent.addChild(server)
        }
        let document = XMLDocument(rootElement: root)
        document.characterEncoding = "UTF-8"
        try document.xmlData(options: [.nodePrettyPrint]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func encodeRemoteDir(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return "1 0" + parts.map { " \($0.unicodeScalars.count) \($0)" }.joined()
    }

    static func decodeRemoteDir(_ raw: String) -> String {
        if raw.hasPrefix("/") { return raw }
        if raw == "1 0" || raw == "0 0" { return "/" }
        guard raw.hasPrefix("1 0 ") || raw.hasPrefix("0 0 ") else { return "/" }
        // wxChar is UTF-32 on macOS/Linux. Accept UTF-16 counts from Windows exports too.
        func parse(utf16: Bool) -> String? {
            var rest = String(raw.dropFirst(4))
            var parts: [String] = []
            while !rest.isEmpty {
                guard let space = rest.firstIndex(of: " "), let length = Int(rest[..<space]), length > 0 else { return nil }
                rest = String(rest[rest.index(after: space)...])
                if utf16 {
                    let units = Array(rest.utf16)
                    guard units.count >= length else { return nil }
                    parts.append(String(decoding: units.prefix(length), as: UTF16.self))
                    rest = String(decoding: units.dropFirst(length), as: UTF16.self)
                } else {
                    let units = Array(rest.unicodeScalars.map(\.value))
                    guard units.count >= length else { return nil }
                    parts.append(String(decoding: units.prefix(length), as: UTF32.self))
                    rest = String(decoding: units.dropFirst(length), as: UTF32.self)
                }
                if !rest.isEmpty {
                    guard rest.hasPrefix(" ") else { return nil }
                    rest.removeFirst()
                }
            }
            return "/" + parts.joined(separator: "/")
        }
        return parse(utf16: false) ?? parse(utf16: true) ?? "/"
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "macmd.filezilla", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
