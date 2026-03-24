import AppKit
import Foundation

struct FileOps {
    private struct InspectSummary {
        var selectedItems = 0
        var selectedFiles = 0
        var selectedFolders = 0
        var containedFiles = 0
        var containedFolders = 0
        var totalBytes: Int64 = 0
    }

    // MARK: - Open

    static func open(items: [FileItem], editor: Bool) {
        for item in items {
            guard !item.isVirtual else { continue }
            if editor {
                NSWorkspace.shared.open([item.url],
                                        withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                        configuration: .init(), completionHandler: nil)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    static func openTerminal(at directory: URL) {
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: .init(),
            completionHandler: nil
        )
    }

    // MARK: - Copy

    static func copy(items: [FileItem], to dest: URL, window: NSWindow, completion: @escaping () -> Void) {
        guard !items.isEmpty else { return }
        let destStr = items.count == 1
            ? "Kopírovať '\(items[0].name)' do:"
            : "Kopírovať \(items.count) položiek do:"

        askDestination(message: destStr, defaultPath: dest.path, window: window) { destPath in
            guard let destPath else { return }
            let destURL = URL(fileURLWithPath: destPath)
            FileOperationEngine.shared.enqueue(kind: .copy, items: items, destination: destURL, window: window, completion: completion)
        }
    }

    // MARK: - Move

    static func move(items: [FileItem], to dest: URL, window: NSWindow, completion: @escaping () -> Void) {
        guard !items.isEmpty else { return }
        let msg = items.count == 1
            ? "Presunúť '\(items[0].name)' do:"
            : "Presunúť \(items.count) položiek do:"

        askDestination(message: msg, defaultPath: dest.path, window: window) { destPath in
            guard let destPath else { return }
            let destURL = URL(fileURLWithPath: destPath)
            FileOperationEngine.shared.enqueue(kind: .move, items: items, destination: destURL, window: window, completion: completion)
        }
    }

    // MARK: - Delete

    static func delete(items: [FileItem], window: NSWindow, permanently: Bool = false, completion: @escaping () -> Void) {
        guard !items.isEmpty else { return }
        let msg = items.count == 1
            ? "Zmazať '\(items[0].name)'?"
            : "Zmazať \(items.count) označených položiek?"

        let alert = NSAlert()
        alert.messageText = permanently ? "Zmazať natrvalo" : "Zmazať"
        alert.informativeText = msg
        alert.addButton(withTitle: "Zmazať")
        alert.addButton(withTitle: "Zrušiť")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { resp in
            guard resp == .alertFirstButtonReturn else { return }
            runWithProgress(title: "Mazanie", items: items, window: window) { item in
                if permanently {
                    try FileManager.default.removeItem(at: item.url)
                } else {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                }
            } completion: { completion() }
        }
    }

    static func inspect(items: [FileItem], window: NSWindow) {
        let localItems = items.filter { !$0.isParent && !$0.isVirtual }
        guard !localItems.isEmpty else { return }

        let progressWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
                                      styleMask: [.titled], backing: .buffered, defer: false)
        progressWindow.title = "Počítam veľkosť"

        let label = NSTextField(labelWithString: "Spracovávam…")
        label.font = TC.mono
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let stack = NSStackView(views: [label, spinner])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        progressWindow.contentView?.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let cv = progressWindow.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
                stack.widthAnchor.constraint(equalTo: cv.widthAnchor, constant: -32),
            ])
        }

        window.beginSheet(progressWindow)

        DispatchQueue.global(qos: .userInitiated).async {
            let summary = buildInspectSummary(for: localItems) { name in
                DispatchQueue.main.async {
                    label.stringValue = name
                }
            }
            DispatchQueue.main.async {
                window.endSheet(progressWindow)
                presentInspectSummary(summary, items: localItems, window: window)
            }
        }
    }

    // MARK: - New Folder

    static func createFolder(in dir: URL, window: NSWindow, completion: @escaping (String) -> Void) {
        promptText(
            title: "Nový priečinok",
            message: "Zadaj názov:",
            defaultValue: "Nový priečinok",
            confirmTitle: "Vytvoriť",
            cancelTitle: "Zrušiť",
            window: window
        ) { value in
            guard let value else { return }
            let name = value.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let newURL = dir.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
                completion(name)
            } catch {
                presentError(error, window: window)
            }
        }
    }

    static func compress(items: [FileItem], in dir: URL, window: NSWindow, completion: @escaping () -> Void) {
        let localItems = items.filter { !$0.isParent && !$0.isVirtual }
        guard !localItems.isEmpty else { return }

        let defaultName: String
        if localItems.count == 1 {
            defaultName = "\(localItems[0].name).zip"
        } else {
            defaultName = "Archive.zip"
        }

        promptText(
            title: "Vytvoriť ZIP",
            message: "Názov archívu v aktuálnom priečinku:",
            defaultValue: defaultName,
            confirmTitle: "Vytvoriť",
            cancelTitle: "Zrušiť",
            window: window
        ) { value in
            guard let value else { return }
            var archiveName = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !archiveName.isEmpty else { return }
            if !archiveName.lowercased().hasSuffix(".zip") {
                archiveName += ".zip"
            }

            let archiveURL = dir.appendingPathComponent(archiveName)
            runWithProgress(title: "ZIP", items: localItems, window: window, operation: { _ in
                try zip(items: localItems, workingDirectory: dir, destination: archiveURL)
            }, completion: {
                completion()
            }, perItem: false)
        }
    }

    static func listZipArchive(_ archiveURL: URL) throws -> [String] {
        try runCommand(
            "/usr/bin/unzip",
            arguments: ["-Z1", archiveURL.path],
            currentDirectory: archiveURL.deletingLastPathComponent()
        )
        .split(separator: "\n")
        .map { String($0) }
        .filter { !$0.isEmpty }
    }

    static func fileItem(for url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .localizedTypeDescriptionKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDirectory = values.isDirectory ?? false
        return FileItem(
            name: url.lastPathComponent,
            url: url,
            isDirectory: isDirectory,
            typeDescription: values.localizedTypeDescription ?? (isDirectory ? "Folder" : (url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased())),
            size: Int64(values.fileSize ?? 0),
            modDate: values.contentModificationDate ?? .now,
            isMarked: false,
            isParent: false,
            isVirtual: false
        )
    }

    static func runProgress(title: String, items: [FileItem], window: NSWindow,
                            operation: @escaping (FileItem) throws -> Void,
                            completion: @escaping () -> Void,
                            perItem: Bool = true) {
        runWithProgress(title: title, items: items, window: window, operation: operation, completion: completion, perItem: perItem)
    }

    static func promptText(title: String, message: String, defaultValue: String,
                           confirmTitle: String, cancelTitle: String,
                           window: NSWindow,
                           completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        alert.window.initialFirstResponder = field
        field.selectText(nil)
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                completion(field.stringValue)
            } else {
                completion(nil)
            }
        }
    }

    static func presentError(_ error: Error, window: NSWindow) {
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }

    // MARK: - Helpers

    private static func askDestination(message: String, defaultPath: String,
                                       window: NSWindow, callback: @escaping (String?) -> Void) {
        promptText(
            title: message,
            message: "",
            defaultValue: defaultPath,
            confirmTitle: "OK",
            cancelTitle: "Zrušiť",
            window: window
        ) { value in
            callback(value?.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func runWithProgress(title: String, items: [FileItem], window: NSWindow,
                                        operation: @escaping (FileItem) throws -> Void,
                                        completion: @escaping () -> Void,
                                        perItem: Bool = true) {
        // Show simple progress sheet
        let progressWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
                                       styleMask: [.titled], backing: .buffered, defer: false)
        progressWindow.title = title

        let label = NSTextField(labelWithString: "Spracovávam…")
        label.font = TC.mono
        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = perItem ? Double(items.count) : 1
        bar.isIndeterminate = false

        let stack = NSStackView(views: [label, bar])
        stack.orientation = .vertical
        stack.spacing = 8
        progressWindow.contentView?.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let cv = progressWindow.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
                stack.widthAnchor.constraint(equalTo: cv.widthAnchor, constant: -32),
            ])
        }

        window.beginSheet(progressWindow)

        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            for (i, item) in items.enumerated() {
                do {
                    try operation(item)
                    if !perItem { break }
                } catch {
                    errors.append("\(item.name): \(error.localizedDescription)")
                    if !perItem { break }
                }
                let progress = perItem ? Double(i + 1) : 1
                DispatchQueue.main.async {
                    bar.doubleValue = progress
                    label.stringValue = perItem ? item.name : "Spracovávam…"
                }
            }
            DispatchQueue.main.async {
                window.endSheet(progressWindow)
                completion()
                if !errors.isEmpty {
                    let a = NSAlert()
                    a.messageText = "Chyby pri \(title.lowercased())"
                    a.informativeText = errors.joined(separator: "\n")
                    a.beginSheetModal(for: window)
                }
            }
        }
    }

    private static func zip(items: [FileItem], workingDirectory: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let relativeNames = items.map(\.name)
        _ = try runCommand(
            "/usr/bin/zip",
            arguments: ["-r", destination.lastPathComponent] + relativeNames,
            currentDirectory: workingDirectory
        )
    }

    private static func buildInspectSummary(for items: [FileItem], progress: @escaping (String) -> Void) -> InspectSummary {
        var summary = InspectSummary()
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .totalFileSizeKey]

        for item in items {
            progress(item.name)
            summary.selectedItems += 1
            if item.isDirectory {
                summary.selectedFolders += 1
                let nested = directorySummary(at: item.url, resourceKeys: resourceKeys)
                summary.containedFolders += nested.folders
                summary.containedFiles += nested.files
                summary.totalBytes += nested.bytes
            } else {
                summary.selectedFiles += 1
                summary.containedFiles += 1
                summary.totalBytes += fileSize(at: item.url, fallback: item.size)
            }
        }

        return summary
    }

    private static func directorySummary(at directoryURL: URL, resourceKeys: Set<URLResourceKey>) -> (folders: Int, files: Int, bytes: Int64) {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return (0, 0, 0)
        }

        var folders = 0
        var files = 0
        var bytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else { continue }
            if values.isDirectory == true {
                folders += 1
            } else {
                files += 1
                bytes += Int64(values.totalFileAllocatedSize ?? values.totalFileSize ?? values.fileSize ?? 0)
            }
        }

        return (folders, files, bytes)
    }

    private static func fileSize(at url: URL, fallback: Int64) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .totalFileSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return fallback }
        return Int64(values.totalFileAllocatedSize ?? values.totalFileSize ?? values.fileSize ?? Int(fallback))
    }

    private static func presentInspectSummary(_ summary: InspectSummary, items: [FileItem], window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = items.count == 1 ? items[0].name : "Selected items"

        if items.count == 1, let item = items.first {
            if item.isDirectory {
                alert.informativeText = """
                Folder
                Content: \(summary.containedFolders) folders, \(summary.containedFiles) files
                Total size: \(FileItem.formatSize(summary.totalBytes))
                """
            } else {
                alert.informativeText = """
                File
                Size: \(FileItem.formatSize(summary.totalBytes))
                """
            }
        } else {
            alert.informativeText = """
            Selected: \(summary.selectedItems) items (\(summary.selectedFolders) folders, \(summary.selectedFiles) files)
            Content: \(summary.containedFolders) folders, \(summary.containedFiles) files
            Total size: \(FileItem.formatSize(summary.totalBytes))
            """
        }

        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    @discardableResult
    private static func runCommand(_ launchPath: String, arguments: [String], currentDirectory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "macmd.process",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr]
            )
        }
        return stdout
    }
}
