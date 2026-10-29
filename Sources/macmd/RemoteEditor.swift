import AppKit

/// Explicit Save uploads to the captured endpoint, even if the user changes panels.
final class RemoteEditor: NSWindowController, NSWindowDelegate {
    private static var sessions: [RemoteEditor] = []
    private let connection: FTPConnection
    private let path: String
    private var original: Data
    private let text = NSTextView()
    private let saveButton = NSButton(title: "Save to Server", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private var saving = false
    var onSaved: (() -> Void)?

    init(connection: FTPConnection, path: String, data: Data) throws {
        guard data.count <= 10 * 1024 * 1024, let contents = String(data: data, encoding: .utf8), !contents.contains("\0") else {
            throw RemoteTrust.error("The built-in remote editor supports UTF-8 text files up to 10 MB. Download other files with F5.")
        }
        self.connection = connection; self.path = path; self.original = data
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "\(connection.displayName): \(path)"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = contents
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = text
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        saveButton.target = self; saveButton.action = #selector(save)
        saveButton.keyEquivalent = "s"; saveButton.keyEquivalentModifierMask = [.command]
        let bar = NSStackView(views: [saveButton, status])
        bar.spacing = 12
        let stack = NSStackView(views: [scroll, bar]); stack.orientation = .vertical; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -12),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.center()
        Self.sessions.append(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func save() {
        guard !saving else { return }
        let data = Data(text.string.utf8)
        saving = true; saveButton.isEnabled = false; status.stringValue = "Uploading…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let current = try FTPBrowser.download(connection: self.connection, remotePath: self.path)
                defer { try? FileManager.default.removeItem(at: current) }
                guard try Data(contentsOf: current) == self.original else { throw RemoteTrust.error("The server file changed since it was opened. Reopen it before saving to avoid overwriting someone else's changes.") }
                let local = FileManager.default.temporaryDirectory.appendingPathComponent("macmd-edit-\(UUID())")
                defer { try? FileManager.default.removeItem(at: local) }
                try data.write(to: local)
                try FTPBrowser.upload(connection: self.connection, localURL: local, to: self.path)
                DispatchQueue.main.async {
                    self.original = data; self.saving = false; self.saveButton.isEnabled = true
                    self.status.stringValue = "Saved to server"; self.onSaved?()
                }
            } catch {
                DispatchQueue.main.async {
                    self.saving = false; self.saveButton.isEnabled = true; self.status.stringValue = "Upload failed"
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !saving else { return false }
        guard Data(text.string.utf8) != original else { return true }
        let alert = NSAlert(); alert.messageText = "Discard unsaved remote changes?"
        alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: "Discard")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func windowWillClose(_ notification: Notification) { Self.sessions.removeAll { $0 === self } }
}
