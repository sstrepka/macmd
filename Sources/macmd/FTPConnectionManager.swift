import AppKit
import UniformTypeIdentifiers

final class FTPConnectionManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onConnect: ((FTPConnection) -> Void)?

    private var connections: [FTPConnection] = []
    private let connectionLoader: () -> [FTPConnection]
    private var selectedID: UUID?
    private var updatingForm = false

    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let hostField = NSTextField()
    private let portField = NSTextField()
    private let userField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let pathField = NSTextField()
    private let commentsField = NSTextField()
    private let accountField = NSTextField()
    private let encodingField = NSTextField()
    private let protocolPopup = NSPopUpButton()
    private let logonPopup = NSPopUpButton()
    private let passivePopup = NSPopUpButton()
    private let privateKeyField = NSTextField()
    private let certificateField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    override convenience init(window: NSWindow?) {
        self.init(window: window, connectionLoader: { FTPConnectionStore.shared.connections() })
    }

    init(window: NSWindow?, connectionLoader: @escaping () -> [FTPConnection]) {
        self.connectionLoader = connectionLoader
        let panel = DialogWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "FTP / SFTP Connections"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildUI()
        reloadConnections(select: connections.first?.id)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func show(select connectionID: UUID? = nil) {
        reloadConnections(select: connectionID ?? selectedID ?? connections.first?.id)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshImportedConnections() { reloadConnections(select: selectedID) }

    func openNewConnection() {
        updatingForm = true
        defer { updatingForm = false }
        if let current = selectedConnection, current.host.isEmpty, current.name.isEmpty {
            return
        }
        let connection = FTPConnection(name: "", host: "", username: "", password: "")
        connections.append(connection)
        selectedID = connection.id
        refreshListSelection()
        loadSelectionIntoForm()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        connections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = connections[row]
        let identifier = NSUserInterfaceItemIdentifier("FTPConnectionCell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let value = NSTextField(labelWithString: "")
            value.identifier = identifier
            value.lineBreakMode = .byTruncatingMiddle
            return value
        }()
        field.stringValue = item.resolvedName
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingForm else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < connections.count else { return }
        saveCurrentFormIntoModel()
        selectedID = connections[row].id
        loadSelectionIntoForm()
    }

    @objc private func protocolChanged() {
        if [21, 22, 990].contains(Int(portField.stringValue) ?? 21) {
            let proto = protocolType(for: protocolPopup.indexOfSelectedItem)
            portField.stringValue = String(proto == 1 ? 22 : proto == 3 ? 990 : 21)
        }
    }

    @objc private func addConnection() {
        saveCurrentFormIntoModel()
        openNewConnection()
    }

    @objc private func deleteConnection() {
        guard let id = selectedID else { return }
        connections.removeAll { $0.id == id }
        FTPConnectionStore.shared.remove(id: id)
        let next = connections.first?.id
        reloadConnections(select: next)
    }

    @objc private func saveConnections() {
        saveCurrentFormIntoModel()
        guard FTPConnectionStore.shared.save(connections) else { showError(FTPConnectionStore.shared.lastError ?? RemoteTrust.error("Could not save credentials to macOS Keychain.")); return }
        reloadConnections(select: selectedID)
        statusLabel.stringValue = "Saved"
    }

    @objc private func connectSelected() {
        saveCurrentFormIntoModel()
        guard FTPConnectionStore.shared.save(connections) else { showError(FTPConnectionStore.shared.lastError ?? RemoteTrust.error("Could not save credentials to macOS Keychain.")); return }
        guard let connection = selectedConnection else { return }
        onConnect?(connection)
    }

    @objc private func importSites() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try FileZillaImport.loadConnections(from: url)
            saveCurrentFormIntoModel()
            guard FTPConnectionStore.shared.importConnections(imported) else { throw FTPConnectionStore.shared.lastError ?? RemoteTrust.error("Could not save and verify imported credentials in macOS Keychain.") }
            reloadConnections(select: imported.first?.id)
            statusLabel.stringValue = "Imported \(imported.count) sites"
        } catch { showError(error) }
    }

    @objc private func exportSites() {
        saveCurrentFormIntoModel()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "FileZilla.xml"
        panel.message = "Export includes passwords, encoded as Base64, just like FileZilla."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try FileZillaImport.export(connections, to: url); statusLabel.stringValue = "Exported" }
        catch { showError(error) }
    }

    @objc private func trustTLS() {
        saveCurrentFormIntoModel()
        guard let connection = selectedConnection, [0, 3, 4].contains(connection.protocolType), !connection.host.isEmpty else {
            statusLabel.stringValue = "Select a saved FTPS site first"; return
        }
        statusLabel.stringValue = "Reading certificate…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try RemoteTrust.trustCertificate(connection)
                DispatchQueue.main.async { self.statusLabel.stringValue = "Certificate trusted" }
            } catch { DispatchQueue.main.async { self.showError(error) } }
        }
    }

    @objc private func resetTrust() {
        saveCurrentFormIntoModel()
        guard let connection = selectedConnection, !connection.host.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Forget trust for \(connection.host):\(connection.port)?"
        alert.informativeText = "The next SFTP connection will ask you to verify the host key again. Saved and session TLS certificate exceptions will also be removed."
        alert.addButton(withTitle: "Forget"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try RemoteTrust.forgetTLSException(connection)
            if let certificate = RemoteTrust.certificate(for: connection) { try FileManager.default.removeItem(at: certificate) }
            if FileManager.default.fileExists(atPath: RemoteTrust.knownHosts.path) {
                let host = connection.port == 22 ? connection.host : "[\(connection.host)]:\(connection.port)"
                let result = try RemoteTrust.run("/usr/bin/ssh-keygen", ["-R", host, "-f", RemoteTrust.knownHosts.path])
                guard result.0 == 0 else { throw RemoteTrust.error(String(decoding: result.1, as: UTF8.self)) }
            }
            statusLabel.stringValue = "Trust reset"
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    @objc private func browsePrivateKey() {
        choosePath(for: privateKeyField, title: "Choose Private Key")
    }

    @objc private func browseCertificate() {
        choosePath(for: certificateField, title: "Choose Certificate")
    }

    private var selectedConnection: FTPConnection? {
        guard let id = selectedID else { return nil }
        return connections.first(where: { $0.id == id })
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        let listContainer = NSView()
        let formContainer = NSView()
        split.addArrangedSubview(listContainer)
        split.addArrangedSubview(formContainer)

        content.addSubview(split)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.documentView = tableView
        listContainer.addSubview(scroll)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Saved Connections"
        col.width = 260
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowSizeStyle = .medium
        tableView.target = self
        tableView.doubleAction = #selector(connectSelected)

        let listButtons = NSStackView()
        listButtons.orientation = .horizontal
        listButtons.spacing = 8
        listButtons.distribution = .fillEqually
        listButtons.translatesAutoresizingMaskIntoConstraints = false

        listButtons.addArrangedSubview(makeButton(title: "Add", action: #selector(addConnection)))
        listButtons.addArrangedSubview(makeButton(title: "Delete", action: #selector(deleteConnection)))
        listButtons.addArrangedSubview(makeButton(title: "Connect", action: #selector(connectSelected)))
        listContainer.addSubview(listButtons)

        let formScroll = NSScrollView()
        formScroll.translatesAutoresizingMaskIntoConstraints = false
        formScroll.hasVerticalScroller = true
        formScroll.drawsBackground = false
        formContainer.addSubview(formScroll)

        let formDocument = NSView()
        formDocument.translatesAutoresizingMaskIntoConstraints = false
        formScroll.documentView = formDocument

        protocolPopup.addItems(withTitles: ["FTP (TLS if available)", "SFTP", "FTPS (Explicit TLS)", "FTPS (Implicit TLS)", "FTP (Plain)", "Unsupported (preserved)"])
        protocolPopup.target = self
        protocolPopup.action = #selector(protocolChanged)
        logonPopup.addItems(withTitles: ["Anonymous", "Normal", "Ask Password", "Interactive", "Account", "Key File"])
        passivePopup.addItems(withTitles: ["Default", "Active", "Passive"])

        let privateKeyButton = makeButton(title: "Choose", action: #selector(browsePrivateKey))
        let certificateButton = makeButton(title: "Choose", action: #selector(browseCertificate))

        let rows: [[NSView]] = [
            [label("Name"), nameField],
            [label("Server"), hostField],
            [label("Port"), portField],
            [label("Protocol"), protocolPopup],
            [label("Login Type"), logonPopup],
            [label("User"), userField],
            [label("Password"), passwordField],
            [label("Account"), accountField],
            [label("Remote Path"), pathField],
            [label("Passive Mode"), passivePopup],
            [label("Encoding"), encodingField],
            [label("Private Key"), stack([privateKeyField, privateKeyButton])],
            [label("Certificate"), stack([certificateField, certificateButton])],
            [label("Comments"), commentsField]
        ]

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        formDocument.addSubview(grid)

        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 8
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .right
        statusLabel.textColor = .secondaryLabelColor
        bottomBar.addArrangedSubview(makeButton(title: "Save", action: #selector(saveConnections)))
        bottomBar.addArrangedSubview(makeButton(title: "Import XML", action: #selector(importSites)))
        bottomBar.addArrangedSubview(makeButton(title: "Export XML", action: #selector(exportSites)))
        bottomBar.addArrangedSubview(makeButton(title: "Trust TLS…", action: #selector(trustTLS)))
        bottomBar.addArrangedSubview(makeButton(title: "Reset Trust…", action: #selector(resetTrust)))
        bottomBar.addArrangedSubview(makeButton(title: "Close", action: #selector(closeWindow)))
        bottomBar.addArrangedSubview(statusLabel)
        formContainer.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: listButtons.topAnchor, constant: -10),

            listButtons.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            listButtons.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            listButtons.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),

            formScroll.topAnchor.constraint(equalTo: formContainer.topAnchor),
            formScroll.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            formScroll.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            formScroll.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -10),

            bottomBar.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor),

            grid.topAnchor.constraint(equalTo: formDocument.topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: formDocument.leadingAnchor, constant: 8),
            grid.trailingAnchor.constraint(equalTo: formDocument.trailingAnchor, constant: -8),
            grid.bottomAnchor.constraint(equalTo: formDocument.bottomAnchor, constant: -8),
            grid.widthAnchor.constraint(equalTo: formScroll.contentView.widthAnchor, constant: -16)
        ])

        split.setPosition(280, ofDividerAt: 0)
        for row in 0..<grid.numberOfRows {
            grid.cell(atColumnIndex: 1, rowIndex: row).contentView?.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        }
    }

    private func reloadConnections(select connectionID: UUID?) {
        updatingForm = true
        defer { updatingForm = false }
        connections = connectionLoader()
        if connections.isEmpty {
            let blank = FTPConnection(name: "", host: "", username: "", password: "")
            connections = [blank]
        }
        selectedID = connectionID.flatMap { id in connections.contains(where: { $0.id == id }) ? id : nil } ?? connections.first?.id
        tableView.reloadData()
        refreshListSelection()
        loadSelectionIntoForm()
    }

    private func refreshListSelection() {
        guard let id = selectedID, let index = connections.firstIndex(where: { $0.id == id }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    private func loadSelectionIntoForm() {
        guard let connection = selectedConnection else { return }
        nameField.stringValue = connection.name
        hostField.stringValue = connection.host
        portField.stringValue = "\(connection.port)"
        userField.stringValue = connection.username
        passwordField.stringValue = connection.password
        pathField.stringValue = connection.initialPath
        commentsField.stringValue = connection.comments
        accountField.stringValue = connection.account
        encodingField.stringValue = connection.encodingType
        privateKeyField.stringValue = connection.privateKeyPath
        certificateField.stringValue = connection.certificatePath
        protocolPopup.selectItem(at: popupIndex(for: connection.protocolType))
        logonPopup.selectItem(at: popupLoginIndex(for: connection.logonType))
        passivePopup.selectItem(at: popupPassiveIndex(for: connection.passiveMode))
    }

    private func saveCurrentFormIntoModel() {
        guard let id = selectedID, let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[index].host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[index].port = Int(portField.stringValue) ?? 21
        connections[index].username = userField.stringValue
        connections[index].password = passwordField.stringValue
        connections[index].initialPath = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[index].comments = commentsField.stringValue
        connections[index].account = accountField.stringValue
        connections[index].encodingType = encodingField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Auto" : encodingField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[index].privateKeyPath = privateKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[index].certificatePath = certificateField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[index].protocolType = protocolType(for: protocolPopup.indexOfSelectedItem)
        connections[index].logonType = loginType(for: logonPopup.indexOfSelectedItem)
        connections[index].passiveMode = passiveMode(for: passivePopup.indexOfSelectedItem)
        let wasUpdating = updatingForm
        updatingForm = true
        tableView.reloadData()
        updatingForm = wasUpdating
    }

    @objc private func closeWindow() {
        saveCurrentFormIntoModel()
        guard FTPConnectionStore.shared.save(connections.filter { !$0.host.isEmpty }) else { showError(FTPConnectionStore.shared.lastError ?? RemoteTrust.error("Could not save credentials to macOS Keychain.")); return }
        close()
    }

    private func choosePath(for field: NSTextField, title: String) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            field.stringValue = panel.url?.path ?? ""
        }
    }

    private func label(_ title: String) -> NSTextField {
        NSTextField(labelWithString: title)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        if let first = views.first {
            first.translatesAutoresizingMaskIntoConstraints = false
            first.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        }
        return stack
    }

    private func popupIndex(for protocolType: Int) -> Int {
        switch protocolType {
        case 1:
            return 1
        case 4:
            return 2
        case 3:
            return 3
        case 0: return 0
        case 6: return 4
        default: return 5
        }
    }

    private func protocolType(for index: Int) -> Int {
        switch index {
        case 1:
            return 1
        case 2:
            return 4
        case 3:
            return 3
        case 4: return 6
        case 5: return selectedConnection?.protocolType ?? 0
        default: return 0
        }
    }

    private func popupLoginIndex(for loginType: Int) -> Int {
        let mapping = [0, 1, 2, 3, 4, 5]
        return mapping.contains(loginType) ? loginType : 1
    }

    private func loginType(for index: Int) -> Int {
        index
    }

    private func popupPassiveIndex(for mode: String) -> Int {
        switch mode {
        case "MODE_ACTIVE":
            return 1
        case "MODE_PASSIVE":
            return 2
        default:
            return 0
        }
    }

    private func passiveMode(for index: Int) -> String {
        switch index {
        case 1:
            return "MODE_ACTIVE"
        case 2:
            return "MODE_PASSIVE"
        default:
            return "MODE_DEFAULT"
        }
    }
}

#if MACMD_REMOTE_TESTS
extension FTPConnectionManagerWindowController {
    static func verifyImportedCredentials(_ imported: [FTPConnection]) {
        let controller = FTPConnectionManagerWindowController(window: nil, connectionLoader: { imported })
        func verify() {
            for expected in imported {
                guard let actual = controller.connections.first(where: { $0.id == expected.id }) else { preconditionFailure("Missing imported site") }
                if actual != expected {
                    let lhs = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(actual)) as! [String: Any]
                    let rhs = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(expected)) as! [String: Any]
                    let changed = Set(lhs.keys).union(rhs.keys).filter { !NSDictionary(dictionary: ["v": lhs[$0] ?? NSNull()]).isEqual(to: ["v": rhs[$0] ?? NSNull()]) }.sorted()
                    FileHandle.standardError.write(Data("Changed fields: \(changed.joined(separator: ", "))\n".utf8))
                    preconditionFailure("Account changed during selection/reload")
                }
            }
        }
        verify()
        controller.reloadConnections(select: UUID())
        precondition(controller.selectedID == imported.first?.id, "Reimport must resolve a fresh imported ID to an existing site")
        verify()
        for expected in imported {
            controller.reloadConnections(select: expected.id)
            precondition(controller.passwordField.stringValue == expected.password, "Password not loaded into form")
            controller.saveCurrentFormIntoModel()
            verify()
        }
        // A toolbar import can refresh an already-open manager holding stale blank fields.
        controller.passwordField.stringValue = ""
        controller.refreshImportedConnections()
        verify()
        for index in imported.indices.reversed() {
            controller.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            verify()
            precondition(controller.passwordField.stringValue == imported[index].password, "Selection loaded wrong password")
        }
        controller.openNewConnection()
        verify()
        controller.window?.close()
    }
}
#endif
