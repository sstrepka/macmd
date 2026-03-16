import AppKit

enum AppearanceMode {
    case system
    case light
    case dark
}

final class ViewState {
    var showHiddenFiles = false
    var appearanceMode: AppearanceMode = .system
    var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}

struct TC {
    static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let monoBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    static func palette(for appearance: NSAppearance?) -> Palette {
        let best = appearance?.bestMatch(from: [.darkAqua, .aqua])
        if best == .darkAqua {
            return Palette(
                windowBackground: NSColor(calibratedWhite: 0.13, alpha: 1),
                panelBackground: NSColor(calibratedWhite: 0.15, alpha: 1),
                headerBackground: NSColor(calibratedWhite: 0.18, alpha: 1),
                footerBackground: NSColor(calibratedWhite: 0.17, alpha: 1),
                border: NSColor(calibratedWhite: 0.28, alpha: 1),
                focusBorder: NSColor.controlAccentColor,
                cursor: NSColor.selectedContentBackgroundColor,
                marked: NSColor.systemOrange,
                primaryText: NSColor(calibratedWhite: 0.92, alpha: 1),
                secondaryText: NSColor(calibratedWhite: 0.72, alpha: 1),
                inputBackground: NSColor(calibratedWhite: 0.11, alpha: 1)
            )
        }

        return Palette(
            windowBackground: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.97, alpha: 1),
            panelBackground: NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.99, alpha: 1),
            headerBackground: NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.955, alpha: 1),
            footerBackground: NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.965, alpha: 1),
            border: NSColor(calibratedRed: 0.79, green: 0.82, blue: 0.86, alpha: 1),
            focusBorder: NSColor.controlAccentColor,
            cursor: NSColor.selectedContentBackgroundColor,
            marked: NSColor.systemOrange,
            primaryText: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1),
            secondaryText: NSColor(calibratedRed: 0.38, green: 0.42, blue: 0.48, alpha: 1),
            inputBackground: NSColor.white
        )
    }
}

struct Palette {
    let windowBackground: NSColor
    let panelBackground: NSColor
    let headerBackground: NSColor
    let footerBackground: NSColor
    let border: NSColor
    let focusBorder: NSColor
    let cursor: NSColor
    let marked: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let inputBackground: NSColor
}

final class BookmarksStore {
    static let shared = BookmarksStore()
    private let key = "macmd.bookmarks"

    func bookmarks() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
    }

    func add(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !paths.contains(url.path) else { return }
        paths.append(url.path)
        paths.sort()
        UserDefaults.standard.set(paths, forKey: key)
    }

    func remove(_ url: URL) {
        let paths = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != url.path }
        UserDefaults.standard.set(paths, forKey: key)
    }

    func contains(_ url: URL) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(url.path)
    }

    func replace(with urls: [URL]) {
        let paths = Array(Set(urls.map(\.path))).sorted()
        UserDefaults.standard.set(paths, forKey: key)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: MainWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        mainWindow = MainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        showFullDiskAccessGuideIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func setupMenu() {
        let menu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit macmd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open", action: #selector(menuOpen), keyEquivalent: "\r")
        fileMenu.addItem(withTitle: "Open in Terminal", action: #selector(menuTerminal), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Compress to ZIP", action: #selector(menuZip), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Copy", action: #selector(menuCopy), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Rename", action: #selector(menuRename), keyEquivalent: "")
        fileMenu.addItem(withTitle: "New Folder", action: #selector(menuNewFolder), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Trash", action: #selector(menuDelete), keyEquivalent: "")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "System Appearance", action: #selector(menuAppearanceSystem), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Light Appearance", action: #selector(menuAppearanceLight), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Dark Appearance", action: #selector(menuAppearanceDark), keyEquivalent: "")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Toggle Hidden Files", action: #selector(menuToggleHidden), keyEquivalent: ".")
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)

        let bookmarksItem = NSMenuItem()
        let bookmarksMenu = NSMenu(title: "Bookmarks")
        bookmarksMenu.addItem(withTitle: "Show Bookmarks", action: #selector(menuBookmarks), keyEquivalent: "d")
        bookmarksMenu.addItem(withTitle: "Bookmark Current Folder", action: #selector(menuBookmarkCurrent), keyEquivalent: "")
        bookmarksMenu.addItem(.separator())
        bookmarksMenu.addItem(withTitle: "Default Directory", action: #selector(menuDefaultDirectory), keyEquivalent: "")
        bookmarksItem.submenu = bookmarksMenu
        menu.addItem(bookmarksItem)

        NSApp.mainMenu = menu
    }

    @objc private func menuOpen() { mainWindow?.openSelected() }
    @objc private func menuTerminal() { mainWindow?.openTerminal() }
    @objc private func menuZip() { mainWindow?.compressSelected() }
    @objc private func menuCopy() { mainWindow?.copySelected() }
    @objc private func menuRename() { mainWindow?.renameSelected() }
    @objc private func menuNewFolder() { mainWindow?.createFolder() }
    @objc private func menuDelete() { mainWindow?.deleteSelected() }
    @objc private func menuAppearanceSystem() { mainWindow?.setAppearanceMode(.system) }
    @objc private func menuAppearanceLight() { mainWindow?.setAppearanceMode(.light) }
    @objc private func menuAppearanceDark() { mainWindow?.setAppearanceMode(.dark) }
    @objc private func menuToggleHidden() { mainWindow?.toggleHiddenFiles() }
    @objc private func menuBookmarks() { mainWindow?.activePanel.showBookmarksMenu() }
    @objc private func menuBookmarkCurrent() { mainWindow?.activePanel.addCurrentFolderBookmark() }
    @objc private func menuDefaultDirectory() { mainWindow?.goToDefaultDirectory() }

    private func showFullDiskAccessGuideIfNeeded() {
        let key = "macmd.didShowFullDiskAccessGuide"
        guard !UserDefaults.standard.bool(forKey: key), let window = mainWindow else { return }

        let alert = NSAlert()
        alert.messageText = "Allow Full Disk Access"
        alert.informativeText = "macmd cannot grant Full Disk Access itself. Enable it manually in Privacy & Security, then add /Users/mac/Applications/macmd.app if it is not listed automatically."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Show App")
        alert.addButton(withTitle: "Later")
        alert.beginSheetModal(for: window) { response in
            UserDefaults.standard.set(true, forKey: key)
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            } else if response == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/Users/mac/Applications/macmd.app")])
            }
        }
    }
}

final class MainWindow: NSWindow, NSTextFieldDelegate {
    let leftPanel = FilePanel()
    let rightPanel = FilePanel()
    let viewState = ViewState()
    private let locationsButton = NSButton()
    private let favoritesButton = NSButton()
    private let downloadsButton = NSButton()
    private let documentsButton = NSButton()
    private let toolbarButton = NSButton()
    private let terminalButton = NSButton()
    private let syncButton = NSButton()
    private let terminalPathLabel = NSTextField(labelWithString: "")
    private let terminalInput = NSTextField()
    private let topBar = NSView()
    private let statusBar = NSView()
    private let terminalBar = NSView()
    private let functionBar = NSView()
    private let divider = NSView()
    private(set) var activePanel: FilePanel
    var currentPalette: Palette {
        TC.palette(for: effectiveAppearance)
    }

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        activePanel = leftPanel
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1300, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        build()
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    }

    override func keyDown(with event: NSEvent) {
        if handleFunctionKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    func setActive(_ panel: FilePanel, focus: Bool) {
        activePanel = panel
        leftPanel.setPanelActive(leftPanel === panel)
        rightPanel.setPanelActive(rightPanel === panel)
        refreshTerminalLine()
        if focus {
            makeFirstResponder(panel.tableView)
        }
    }

    func openSelected() {
        activePanel.openCurrent()
    }

    func openTerminal() {
        guard let folder = activePanel.currentDirectoryForOperations else { return }
        FileOps.openTerminal(at: folder)
    }

    func compressSelected() {
        guard let folder = activePanel.currentDirectoryForOperations else { return }
        FileOps.compress(items: activePanel.operationItems, in: folder, window: self) {
            self.activePanel.reloadKeepPos()
        }
    }

    func copySelected() {
        let destination = activePanel === leftPanel ? rightPanel : leftPanel
        guard let target = destination.currentDirectoryForOperations else { return }
        FileOps.copy(items: activePanel.operationItems, to: target, window: self) {
            self.activePanel.reloadKeepPos()
            destination.reloadKeepPos()
        }
    }

    func renameSelected() {
        activePanel.beginRename()
    }

    func createFolder() {
        guard let folder = activePanel.currentDirectoryForOperations else { return }
        FileOps.createFolder(in: folder, window: self) { name in
            self.activePanel.reloadKeepPos(selectingName: name)
        }
    }

    func deleteSelected() {
        FileOps.delete(items: activePanel.operationItems, window: self) {
            self.activePanel.reloadKeepPos()
        }
    }

    func deleteSelectedPermanently() {
        FileOps.delete(items: activePanel.operationItems, window: self, permanently: true) {
            self.activePanel.reloadKeepPos()
        }
    }

    func toggleHiddenFiles() {
        viewState.showHiddenFiles.toggle()
        leftPanel.reloadKeepPos()
        rightPanel.reloadKeepPos()
    }

    func syncOtherPanelToCurrent() {
        let source = activePanel
        let destination = activePanel === leftPanel ? rightPanel : leftPanel
        guard let folder = source.currentDirectoryForOperations else { return }
        destination.navigate(to: folder)
    }

    func goToDefaultDirectory() {
        activePanel.navigate(to: viewState.defaultDirectory)
    }

    func addCurrentFolderToFavorites() {
        guard let folder = activePanel.currentDirectoryForOperations else { return }
        BookmarksStore.shared.add(folder)
    }

    func removeCurrentFolderFromFavorites() {
        guard let folder = activePanel.currentDirectoryForOperations else { return }
        BookmarksStore.shared.remove(folder)
    }

    func openFavorite(_ url: URL) {
        activePanel.navigate(to: url)
    }

    func openLocation(_ url: URL) {
        activePanel.navigate(to: url)
    }

    func openDownloads() {
        openLocation(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
    }

    func openDocuments() {
        openLocation(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
    }

    func editFavorites() {
        let alert = NSAlert()
        alert.messageText = "Edit Favorites"
        alert.informativeText = "One folder path per line."

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
        let textView = NSTextView(frame: scroll.bounds)
        textView.font = TC.mono
        textView.isRichText = false
        textView.string = BookmarksStore.shared.bookmarks().map(\.path).joined(separator: "\n")
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = textView

        alert.beginSheetModal(for: self) { response in
            guard response == .alertFirstButtonReturn else { return }
            let urls = textView.string
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
            BookmarksStore.shared.replace(with: urls)
        }
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        viewState.appearanceMode = mode
        switch mode {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        applyTheme()
    }

    private func build() {
        title = "macmd"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 900, height: 640)
        if let screen = NSScreen.main {
            setFrame(screen.visibleFrame.insetBy(dx: 18, dy: 24), display: true)
        }

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = currentPalette.windowBackground.cgColor
        contentView = content

        buildTopBar()
        buildStatusBar()
        buildTerminalBar()
        buildFunctionBar()
        divider.wantsLayer = true

        content.addSubview(topBar)
        content.addSubview(leftPanel)
        content.addSubview(divider)
        content.addSubview(rightPanel)
        content.addSubview(statusBar)
        content.addSubview(terminalBar)
        content.addSubview(functionBar)

        for view in [topBar, leftPanel, divider, rightPanel, statusBar, terminalBar, functionBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 40),

            leftPanel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            leftPanel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            leftPanel.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -8),

            divider.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: 8),
            divider.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: leftPanel.topAnchor),
            divider.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),

            rightPanel.topAnchor.constraint(equalTo: leftPanel.topAnchor),
            rightPanel.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 8),
            rightPanel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            rightPanel.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
            leftPanel.widthAnchor.constraint(equalTo: rightPanel.widthAnchor),

            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            statusBar.bottomAnchor.constraint(equalTo: terminalBar.topAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 26),

            terminalBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            terminalBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            terminalBar.bottomAnchor.constraint(equalTo: functionBar.topAnchor),
            terminalBar.heightAnchor.constraint(equalToConstant: 24),

            functionBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            functionBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            functionBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            functionBar.heightAnchor.constraint(equalToConstant: 34)
        ])

        leftPanel.attach(to: self)
        rightPanel.attach(to: self)
        leftPanel.onLocationChanged = { [weak self] in self?.refreshTerminalLine() }
        rightPanel.onLocationChanged = { [weak self] in self?.refreshTerminalLine() }

        let initial = viewState.defaultDirectory
        leftPanel.navigate(to: initial)
        rightPanel.navigate(to: initial)
        setActive(leftPanel, focus: true)
        applyTheme()
    }

    private func buildTopBar() {
        topBar.wantsLayer = true
        locationsButton.title = "Locations"
        locationsButton.bezelStyle = .texturedRounded
        locationsButton.target = self
        locationsButton.action = #selector(showLocationsMenu(_:))
        locationsButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        favoritesButton.title = "Favorites"
        favoritesButton.bezelStyle = .texturedRounded
        favoritesButton.target = self
        favoritesButton.action = #selector(showFavoritesMenu(_:))
        favoritesButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        downloadsButton.title = "Downloads"
        downloadsButton.bezelStyle = .texturedRounded
        downloadsButton.target = self
        downloadsButton.action = #selector(openDownloadsFromTopBar)
        downloadsButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        documentsButton.title = "Documents"
        documentsButton.bezelStyle = .texturedRounded
        documentsButton.target = self
        documentsButton.action = #selector(openDocumentsFromTopBar)
        documentsButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        terminalButton.bezelStyle = .texturedRounded
        terminalButton.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Open Terminal")
        terminalButton.imagePosition = .imageOnly
        terminalButton.target = self
        terminalButton.action = #selector(openTerminalFromTopBar)

        syncButton.bezelStyle = .texturedRounded
        syncButton.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Sync Other Pane")
        syncButton.imagePosition = .imageOnly
        syncButton.target = self
        syncButton.action = #selector(syncOtherPanelFromTopBar)

        toolbarButton.bezelStyle = .texturedRounded
        toolbarButton.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "Options")
        toolbarButton.imagePosition = .imageOnly
        toolbarButton.target = self
        toolbarButton.action = #selector(showToolbarMenu(_:))

        topBar.subviews.forEach { $0.removeFromSuperview() }
        topBar.addSubview(locationsButton)
        topBar.addSubview(favoritesButton)
        topBar.addSubview(downloadsButton)
        topBar.addSubview(documentsButton)
        topBar.addSubview(terminalButton)
        topBar.addSubview(syncButton)
        topBar.addSubview(toolbarButton)
        locationsButton.translatesAutoresizingMaskIntoConstraints = false
        favoritesButton.translatesAutoresizingMaskIntoConstraints = false
        downloadsButton.translatesAutoresizingMaskIntoConstraints = false
        documentsButton.translatesAutoresizingMaskIntoConstraints = false
        terminalButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        toolbarButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            locationsButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            locationsButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            favoritesButton.leadingAnchor.constraint(equalTo: locationsButton.trailingAnchor, constant: 8),
            favoritesButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            downloadsButton.leadingAnchor.constraint(equalTo: favoritesButton.trailingAnchor, constant: 8),
            downloadsButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            documentsButton.leadingAnchor.constraint(equalTo: downloadsButton.trailingAnchor, constant: 8),
            documentsButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            terminalButton.trailingAnchor.constraint(equalTo: syncButton.leadingAnchor, constant: -8),
            terminalButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            syncButton.trailingAnchor.constraint(equalTo: toolbarButton.leadingAnchor, constant: -8),
            syncButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            toolbarButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            toolbarButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])
    }

    private func buildStatusBar() {
        statusBar.wantsLayer = true
        let label = NSTextField(labelWithString: "Tab switch pane   Cmd+D bookmarks   Enter open   Backspace up   Space select   Opt+Space size")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = currentPalette.secondaryText
        statusBar.subviews.forEach { $0.removeFromSuperview() }
        statusBar.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
    }

    private func buildTerminalBar() {
        terminalBar.wantsLayer = true

        terminalPathLabel.font = TC.mono
        terminalPathLabel.textColor = currentPalette.secondaryText

        terminalInput.font = TC.mono
        terminalInput.delegate = self
        terminalInput.placeholderString = "Type command and press Enter"
        terminalInput.focusRingType = .none
        terminalInput.isBordered = true
        terminalInput.drawsBackground = true

        let stack = NSStackView(views: [terminalPathLabel, terminalInput])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        terminalBar.subviews.forEach { $0.removeFromSuperview() }
        terminalBar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: terminalBar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: terminalBar.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: terminalBar.centerYAnchor)
        ])
        refreshTerminalLine()
    }

    private func buildFunctionBar() {
        functionBar.wantsLayer = true
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6

        let items: [(String, Selector)] = [
            ("F1 Terminal", #selector(clickF1)),
            ("F2 Zip", #selector(clickF2)),
            ("F3 Open", #selector(clickF3)),
            ("F4 Edit", #selector(clickF4)),
            ("F5 Copy", #selector(clickF5)),
            ("F6 Rename", #selector(clickF6)),
            ("F7 Mkdir", #selector(clickF7)),
            ("F8 Trash", #selector(clickF8)),
            ("F9 Switch", #selector(clickF9)),
            ("F10 Quit", #selector(clickF10))
        ]

        for (title, action) in items {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            button.setButtonType(.momentaryPushIn)
            stack.addArrangedSubview(button)
        }

        functionBar.subviews.forEach { $0.removeFromSuperview() }
        functionBar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: functionBar.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: functionBar.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: functionBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: functionBar.trailingAnchor)
        ])
    }

    @objc private func showToolbarMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let system = NSMenuItem(title: "System Appearance", action: #selector(selectAppearanceSystem), keyEquivalent: "")
        system.target = self
        system.state = viewState.appearanceMode == .system ? .on : .off
        let light = NSMenuItem(title: "Light Appearance", action: #selector(selectAppearanceLight), keyEquivalent: "")
        light.target = self
        light.state = viewState.appearanceMode == .light ? .on : .off
        let dark = NSMenuItem(title: "Dark Appearance", action: #selector(selectAppearanceDark), keyEquivalent: "")
        dark.target = self
        dark.state = viewState.appearanceMode == .dark ? .on : .off
        let hidden = NSMenuItem(title: "Show Hidden Files", action: #selector(toggleHiddenFromToolbar), keyEquivalent: "")
        hidden.target = self
        hidden.state = viewState.showHiddenFiles ? .on : .off
        menu.addItem(system)
        menu.addItem(light)
        menu.addItem(dark)
        menu.addItem(.separator())
        menu.addItem(hidden)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    @objc private func showLocationsMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let staticLocations: [(String, URL, String)] = [
            ("Computer", URL(fileURLWithPath: "/"), "desktopcomputer"),
            ("Applications", URL(fileURLWithPath: "/Applications"), "square.grid.2x2"),
            ("System", URL(fileURLWithPath: "/System"), "gearshape"),
            ("Library", URL(fileURLWithPath: "/Library"), "books.vertical"),
            ("Volumes", URL(fileURLWithPath: "/Volumes"), "externaldrive")
        ]

        for (title, url, symbolName) in staticLocations {
            let item = NSMenuItem(title: title, action: #selector(openLocationFromMenu(_:)), keyEquivalent: "")
            item.representedObject = url
            item.target = self
            item.image = menuSymbol(named: symbolName)
            menu.addItem(item)
        }

        let volumeKeys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsRemovableKey]
        if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(volumeKeys), options: []) {
            let filtered = volumes.filter { $0.path != "/" }.sorted {
                let left = (try? $0.resourceValues(forKeys: volumeKeys).volumeLocalizedName) ?? $0.lastPathComponent
                let right = (try? $1.resourceValues(forKeys: volumeKeys).volumeLocalizedName) ?? $1.lastPathComponent
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }

            if !filtered.isEmpty {
                menu.addItem(.separator())
                for volume in filtered {
                    let values = try? volume.resourceValues(forKeys: volumeKeys)
                    let name = values?.volumeLocalizedName ?? volume.lastPathComponent
                    let suffix = values?.volumeIsRemovable == true ? " (External)" : ((values?.volumeIsInternal == true) ? "" : " (Mounted)")
                    let item = NSMenuItem(title: name + suffix, action: #selector(openLocationFromMenu(_:)), keyEquivalent: "")
                    item.representedObject = volume
                    item.target = self
                    item.image = volumeMenuIcon(for: volume, removable: values?.volumeIsRemovable == true)
                    menu.addItem(item)
                }
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    private func menuSymbol(named symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func volumeMenuIcon(for url: URL, removable: Bool) -> NSImage? {
        if removable {
            return menuSymbol(named: "externaldrive.badge.plus")
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func showFavoritesMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let add = NSMenuItem(title: "Add Current Folder", action: #selector(addCurrentFolderFromFavoritesMenu), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        let remove = NSMenuItem(title: "Remove Current Folder", action: #selector(removeCurrentFolderFromFavoritesMenu), keyEquivalent: "")
        remove.target = self
        if let folder = activePanel.currentDirectoryForOperations {
            remove.isEnabled = BookmarksStore.shared.contains(folder)
        } else {
            remove.isEnabled = false
        }
        menu.addItem(remove)

        let edit = NSMenuItem(title: "Edit Favorites", action: #selector(editFavoritesFromMenu), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        let favorites = BookmarksStore.shared.bookmarks()
        if !favorites.isEmpty {
            menu.addItem(.separator())
            for favorite in favorites {
                let item = NSMenuItem(title: favorite.path, action: #selector(openFavoriteFromMenu(_:)), keyEquivalent: "")
                item.representedObject = favorite
                item.target = self
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    @objc private func selectAppearanceSystem() { setAppearanceMode(.system) }
    @objc private func selectAppearanceLight() { setAppearanceMode(.light) }
    @objc private func selectAppearanceDark() { setAppearanceMode(.dark) }
    @objc private func toggleHiddenFromToolbar() { toggleHiddenFiles() }
    @objc private func addCurrentFolderFromFavoritesMenu() { addCurrentFolderToFavorites() }
    @objc private func removeCurrentFolderFromFavoritesMenu() { removeCurrentFolderFromFavorites() }
    @objc private func editFavoritesFromMenu() { editFavorites() }
    @objc private func openDownloadsFromTopBar() { openDownloads() }
    @objc private func openDocumentsFromTopBar() { openDocuments() }
    @objc private func openLocationFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openLocation(url)
    }
    @objc private func openFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openFavorite(url)
    }
    @objc private func openTerminalFromTopBar() { openTerminal() }
    @objc private func syncOtherPanelFromTopBar() { syncOtherPanelToCurrent() }
    @objc private func clickF1() { openTerminal() }
    @objc private func clickF2() { compressSelected() }
    @objc private func clickF3() { openSelected() }
    @objc private func clickF4() { FileOps.open(items: activePanel.operationItems, editor: true) }
    @objc private func clickF5() { copySelected() }
    @objc private func clickF6() { renameSelected() }
    @objc private func clickF7() { createFolder() }
    @objc private func clickF8() { deleteSelected() }
    @objc private func clickF9() {
        let next = activePanel === leftPanel ? rightPanel : leftPanel
        setActive(next, focus: true)
    }
    @objc private func clickF10() { NSApp.terminate(nil) }

    private func refreshTerminalLine() {
        terminalPathLabel.stringValue = "Terminal: \(activePanel.terminalDisplayPath)"
    }

    private func applyTheme() {
        let palette = currentPalette
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = palette.windowBackground.cgColor
        topBar.layer?.backgroundColor = palette.headerBackground.cgColor
        statusBar.layer?.backgroundColor = palette.headerBackground.cgColor
        terminalBar.layer?.backgroundColor = palette.headerBackground.cgColor
        functionBar.layer?.backgroundColor = palette.footerBackground.cgColor
        divider.layer?.backgroundColor = palette.border.cgColor
        favoritesButton.contentTintColor = palette.primaryText
        downloadsButton.contentTintColor = palette.primaryText
        documentsButton.contentTintColor = palette.primaryText
        locationsButton.contentTintColor = palette.primaryText
        terminalButton.contentTintColor = palette.primaryText
        syncButton.contentTintColor = palette.primaryText
        toolbarButton.contentTintColor = palette.primaryText
        for subview in statusBar.subviews {
            (subview as? NSTextField)?.textColor = palette.secondaryText
        }
        terminalPathLabel.textColor = palette.secondaryText
        terminalInput.textColor = palette.primaryText
        terminalInput.backgroundColor = palette.inputBackground
        leftPanel.applyTheme()
        rightPanel.applyTheme()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === terminalInput else { return }
        let command = terminalInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        terminalInput.stringValue = ""
        runCommandLine(command)
    }

    private func runCommandLine(_ command: String) {
        guard let cwd = activePanel.currentDirectoryForOperations else { return }

        if command == "cd" {
            activePanel.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
            return
        }

        if command.hasPrefix("cd ") {
            let rawTarget = String(command.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let expanded = (rawTarget as NSString).expandingTildeInPath
            let baseURL = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : cwd.appendingPathComponent(expanded)
            let targetURL = baseURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                activePanel.navigate(to: targetURL)
            } else {
                let alert = NSAlert()
                alert.messageText = "Directory not found"
                alert.informativeText = targetURL.path
                alert.beginSheetModal(for: self)
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = cwd

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            NSAlert(error: error).beginSheetModal(for: self)
            return
        }

        process.terminationHandler = { [weak self] proc in
            let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let text = stderr.isEmpty ? stdout : stderr
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                let alert = NSAlert()
                alert.messageText = proc.terminationStatus == 0 ? "Command Output" : "Command Error"
                alert.informativeText = text
                alert.beginSheetModal(for: self)
            }
        }
    }

    private func handleFunctionKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "d" {
            activePanel.showBookmarksMenu()
            return true
        }

        switch event.keyCode {
        case 122:
            openTerminal()
            return true
        case 120:
            compressSelected()
            return true
        case 99:
            openSelected()
            return true
        case 118:
            FileOps.open(items: activePanel.operationItems, editor: true)
            return true
        case 96:
            copySelected()
            return true
        case 97:
            renameSelected()
            return true
        case 98:
            createFolder()
            return true
        case 100:
            deleteSelected()
            return true
        case 117:
            if flags.contains(.shift) {
                deleteSelectedPermanently()
            } else {
                deleteSelected()
            }
            return true
        case 101, 48:
            let next = activePanel === leftPanel ? rightPanel : leftPanel
            setActive(next, focus: true)
            return true
        case 109:
            NSApp.terminate(nil)
            return true
        default:
            return false
        }
    }
}
