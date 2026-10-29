import Foundation
import CryptoKit

/// A private extracted snapshot. Changes are committed through a sibling archive,
/// so a failed compressor never replaces the original.
final class ArchiveSession {
    let archiveURL: URL
    let root: URL
    private var originalData: SHA256.Digest
    private static let lock = NSLock()
    static let extensions: Set<String> = ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz"]
    static var sevenZip: String? {
        ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz", "/opt/homebrew/bin/7z", "/usr/local/bin/7z"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    private static func fingerprint(_ url: URL) throws -> SHA256.Digest {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize()
    }
    static func error(_ message: String) -> NSError {
        NSError(domain: "Archive", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func run(_ executable: String, _ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        // Files avoid pipe-buffer deadlocks with large archive listings.
        let log = directory.appendingPathComponent(".macmd-log-" + UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: log)) ?? ""
            throw error("Archive operation failed.\n" + String(detail.suffix(3000)))
        }
    }
    init(url: URL) throws {
        archiveURL = url
        originalData = try Self.fingerprint(url)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-archive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            // bsdtar rejects absolute paths, '..' traversal and traversal through symlinks.
            // It supports ZIP, TAR and most RAR/7z variants without extra software.
            if url.pathExtension.lowercased() == "gz" && !url.lastPathComponent.lowercased().hasSuffix(".tar.gz") {
                guard let tool = Self.sevenZip else { throw Self.error("Opening a single GZ file requires 7zz.") }
                try Self.run(tool, ["x", "-y", "-o" + root.path, "--", url.path], in: root)
            } else {
                try Self.run("/usr/bin/tar", ["-xf", url.path, "-C", root.path], in: root)
            }
            try validateTree()
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    private func validateTree() throws {
        let base = root.standardizedFileURL.path + "/"
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let url as URL in enumerator {
                if !(url.resolvingSymlinksInPath().standardizedFileURL.path + "/").hasPrefix(base) {
                    throw Self.error("Archive contains a link outside its directory: " + url.lastPathComponent)
                }
            }
        }
    }
    func items(at path: String) -> [FileItem] {
        let directory = root.appendingPathComponent(path)
        let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let parent = FileItem(name: "..", url: directory.deletingLastPathComponent(), isDirectory: true, typeDescription: "", size: 0, modDate: .now, isParent: true, isVirtual: true)
        return [parent] + children.compactMap { url in
            guard var item = FileOps.fileItem(for: url) else { return nil }
            item = FileItem(name: item.name, url: url, isDirectory: item.isDirectory, typeDescription: item.typeDescription, size: item.size, modDate: item.modDate, isParent: false, isVirtual: true)
            return item
        }
    }
    func add(_ items: [FileItem], at path: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard try Self.fingerprint(archiveURL) == originalData else { throw Self.error("Archive changed on disk. Leave it and open it again before copying.") }
        let ext = archiveURL.pathExtension.lowercased()
        guard ext != "rar" else { throw Self.error("RAR archives can be browsed and extracted. Writing RAR requires the proprietary rar tool; use ZIP or 7z instead.") }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-pack-" + UUID().uuidString)
        let output = archiveURL.deletingLastPathComponent().appendingPathComponent(".macmd-" + UUID().uuidString + "-" + archiveURL.lastPathComponent)
        defer { try? FileManager.default.removeItem(at: stage); try? FileManager.default.removeItem(at: output) }
        try FileManager.default.copyItem(at: root, to: stage)
        let destination = stage.appendingPathComponent(path)
        for item in items {
            let target = destination.appendingPathComponent(item.name)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: item.url, to: target)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: stage.path)
        if ext == "zip" || ext == "7z" {
            if let tool = Self.sevenZip {
                try Self.run(tool, ["a", "-t" + ext, output.path, "--"] + names, in: stage)
            } else if ext == "zip" {
                try Self.run("/usr/bin/zip", ["-qr", output.path, "--"] + names, in: stage)
            } else { throw Self.error("Writing 7z archives requires 7zz.") }
        } else if ext == "gz" && !archiveURL.lastPathComponent.lowercased().hasSuffix(".tar.gz") {
            guard names.count == 1, let tool = Self.sevenZip else { throw Self.error("GZ holds one file only. Use .tar.gz for multiple files.") }
            try Self.run(tool, ["a", "-tgzip", output.path, "--"] + names, in: stage)
        } else {
            let flag = ["gz", "tgz"].contains(ext) ? "-czf" : (ext == "bz2" ? "-cjf" : (ext == "xz" ? "-cJf" : "-cf"))
            try Self.run("/usr/bin/tar", [flag, output.path, "--"] + names, in: stage)
        }
        // Validate the completed archive before the atomic replacement.
        let verification = try ArchiveSession(url: output)
        _ = verification
        guard try Self.fingerprint(archiveURL) == originalData else { throw Self.error("Archive changed while packing. Original preserved.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        try FileManager.default.setAttributes([.posixPermissions: attributes[.posixPermissions] ?? 0o644], ofItemAtPath: output.path)
        _ = try FileManager.default.replaceItemAt(archiveURL, withItemAt: output)
        originalData = try Self.fingerprint(archiveURL)
        // Keep URLs already handed to a file operation alive; refresh the snapshot in place.
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            try FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
        for name in names { try FileManager.default.copyItem(at: stage.appendingPathComponent(name), to: root.appendingPathComponent(name)) }
    }
}
