import AppKit

final class FavoritesManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onOpenFavorite: ((URL) -> Void)?

    private var favorites: [URL] = BookmarksStore.shared.bookmarks()
    private let tableView = NSTableView()
    private let pathField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(window: NSWindow?) {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Favorites"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildUI()
        reloadFavorites(select: favorites.first)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        reloadFavorites(select: selectedFavoriteURL)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var selectedFavoriteURL: URL? {
        let row = tableView.selectedRow
        guard row >= 0, row < favorites.count else { return favorites.first }
        return favorites[row]
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        favorites.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("FavoriteCell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let value = NSTextField(labelWithString: "")
            value.identifier = identifier
            value.lineBreakMode = .byTruncatingMiddle
            return value
        }()
        field.stringValue = favorites[row].path
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        pathField.stringValue = selectedFavoriteURL?.path ?? ""
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        true
    }

    @objc private func addFavorite() {
        let newURL = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
        favorites.append(newURL)
        tableView.reloadData()
        select(url: newURL)
        statusLabel.stringValue = "Added"
    }

    @objc private func removeFavorite() {
        let row = tableView.selectedRow
        guard row >= 0, row < favorites.count else { return }
        favorites.remove(at: row)
        BookmarksStore.shared.replace(with: favorites)
        reloadFavorites(select: favorites.indices.contains(max(0, row - 1)) ? favorites[max(0, row - 1)] : favorites.first)
        statusLabel.stringValue = "Removed"
    }

    @objc private func saveFavorite() {
        let trimmed = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = URL(fileURLWithPath: trimmed)
        let row = tableView.selectedRow
        if row >= 0, row < favorites.count {
            favorites[row] = url
        } else {
            favorites.append(url)
        }
        BookmarksStore.shared.replace(with: favorites)
        reloadFavorites(select: url)
        statusLabel.stringValue = "Saved"
    }

    @objc private func openFavorite() {
        guard let favorite = selectedFavoriteURL else { return }
        onOpenFavorite?(favorite)
    }

    @objc private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Favorite Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            self.pathField.stringValue = panel.url?.path ?? self.pathField.stringValue
        }
    }

    @objc private func closeWindow() {
        close()
    }

    private func reloadFavorites(select url: URL?) {
        favorites = BookmarksStore.shared.bookmarks()
        if favorites.isEmpty {
            favorites = [FileManager.default.homeDirectoryForCurrentUser]
        }
        tableView.reloadData()
        select(url: url ?? favorites.first)
    }

    private func select(url: URL?) {
        guard let url, let row = favorites.firstIndex(of: url) else {
            if !favorites.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                pathField.stringValue = favorites[0].path
            }
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        pathField.stringValue = favorites[row].path
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
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        listContainer.addSubview(scroll)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        col.width = 260
        col.title = "Favorites"
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openFavorite)

        let listButtons = NSStackView(views: [
            makeButton(title: "Add", action: #selector(addFavorite)),
            makeButton(title: "Remove", action: #selector(removeFavorite)),
            makeButton(title: "Open", action: #selector(openFavorite))
        ])
        listButtons.orientation = .horizontal
        listButtons.spacing = 8
        listButtons.distribution = .fillEqually
        listButtons.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(listButtons)

        let pathLabel = NSTextField(labelWithString: "Folder")
        let browseButton = makeButton(title: "Choose", action: #selector(chooseFolder))
        let pathRow = NSStackView(views: [pathField, browseButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8
        pathRow.translatesAutoresizingMaskIntoConstraints = false

        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 8
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        bottomBar.addArrangedSubview(makeButton(title: "Save", action: #selector(saveFavorite)))
        bottomBar.addArrangedSubview(makeButton(title: "Close", action: #selector(closeWindow)))
        bottomBar.addArrangedSubview(statusLabel)

        formContainer.addSubview(pathLabel)
        formContainer.addSubview(pathRow)
        formContainer.addSubview(bottomBar)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

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

            pathLabel.topAnchor.constraint(equalTo: formContainer.topAnchor, constant: 8),
            pathLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),

            pathRow.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 8),
            pathRow.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            pathRow.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor)
        ])

        split.setPosition(290, ofDividerAt: 0)
        pathField.translatesAutoresizingMaskIntoConstraints = false
        pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}
