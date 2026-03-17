import AppKit

final class FTPConnectionManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onConnect: ((FTPConnection) -> Void)?

    private var connections: [FTPConnection] = FTPConnectionStore.shared.connections()
    private var selectedID: UUID?

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

    override init(window: NSWindow?) {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "FTP Connections"
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

    func openNewConnection() {
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
        let row = tableView.selectedRow
        guard row >= 0, row < connections.count else { return }
        saveCurrentFormIntoModel()
        selectedID = connections[row].id
        loadSelectionIntoForm()
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
        FTPConnectionStore.shared.save(connections)
        reloadConnections(select: selectedID)
        statusLabel.stringValue = "Saved"
    }

    @objc private func connectSelected() {
        saveCurrentFormIntoModel()
        FTPConnectionStore.shared.save(connections)
        guard let connection = selectedConnection else { return }
        onConnect?(connection)
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

        protocolPopup.addItems(withTitles: ["FTP", "SFTP", "FTPS (Explicit TLS)", "FTPS (Implicit TLS)"])
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
        connections = FTPConnectionStore.shared.connections()
        if connections.isEmpty {
            let blank = FTPConnection(name: "", host: "", username: "", password: "")
            connections = [blank]
        }
        selectedID = connectionID ?? connections.first?.id
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
        tableView.reloadData()
    }

    @objc private func closeWindow() {
        saveCurrentFormIntoModel()
        FTPConnectionStore.shared.save(connections.filter { !$0.host.isEmpty })
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
        case 3:
            return 2
        case 4:
            return 3
        default:
            return 0
        }
    }

    private func protocolType(for index: Int) -> Int {
        switch index {
        case 1:
            return 1
        case 2:
            return 3
        case 3:
            return 4
        default:
            return 0
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
