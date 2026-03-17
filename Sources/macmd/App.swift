import AppKit
import QuickLookUI

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
                focusBorder: NSColor(calibratedWhite: 0.62, alpha: 1),
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
            focusBorder: NSColor(calibratedRed: 0.73, green: 0.76, blue: 0.80, alpha: 1),
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

final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?

    init(url: URL) {
        self.previewItemURL = url
    }
}

final class MainWindow: NSWindow, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let leftPanel = FilePanel()
    let rightPanel = FilePanel()
    let viewState = ViewState()
    private let locationsButton = NSButton()
    private let favoritesButton = NSButton()
    private let downloadsButton = NSButton()
    private let documentsButton = NSButton()
    private let toolbarButton = NSButton()
    private let terminalButton = NSButton()
    private let ftpButton = NSButton()
    private let syncButton = NSButton()
    private let topBar = NSView()
    private let statusBar = NSView()
    private let functionBar = NSView()
    private let divider = NSView()
    private var previewItems: [PreviewItem] = []
    private var ftpManager: FTPConnectionManagerWindowController?
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
        if focus {
            makeFirstResponder(panel.tableView)
        }
    }

    func openSelected() {
        activePanel.openCurrent()
    }

    func presentFTPError(_ error: Error) {
        presentInfoAlert(title: "FTP Connection Failed", message: "macmd 1.0.1\n\n\(error.localizedDescription)")
    }

    func openTerminal() {
        guard let folder = activePanel.currentDirectoryForOperations else { return }
        FileOps.openTerminal(at: folder)
    }

    func showQuickLook(for urls: [URL], index: Int = 0) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        previewItems = urls.map(PreviewItem.init(url:))
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = max(0, min(index, previewItems.count - 1))
        panel.makeKeyAndOrderFront(nil)
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

    func connectFTP(_ connection: FTPConnection) {
        if connection.password.isEmpty && connection.logonType != 5 {
            promptForFTPPassword(connection: connection)
        } else {
            activePanel.navigate(to: connection)
        }
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
        title = "macmd 1.0.1"
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
        buildFunctionBar()
        divider.wantsLayer = true

        content.addSubview(topBar)
        content.addSubview(leftPanel)
        content.addSubview(divider)
        content.addSubview(rightPanel)
        content.addSubview(statusBar)
        content.addSubview(functionBar)

        for view in [topBar, leftPanel, divider, rightPanel, statusBar, functionBar] {
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
            statusBar.bottomAnchor.constraint(equalTo: functionBar.topAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 26),

            functionBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            functionBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            functionBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            functionBar.heightAnchor.constraint(equalToConstant: 34)
        ])

        leftPanel.attach(to: self)
        rightPanel.attach(to: self)
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

        ftpButton.bezelStyle = .texturedRounded
        ftpButton.image = NSImage(systemSymbolName: "network", accessibilityDescription: "FTP")
        ftpButton.imagePosition = .imageOnly
        ftpButton.target = self
        ftpButton.action = #selector(showFTPMenu(_:))

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
        topBar.addSubview(ftpButton)
        topBar.addSubview(syncButton)
        topBar.addSubview(toolbarButton)
        locationsButton.translatesAutoresizingMaskIntoConstraints = false
        favoritesButton.translatesAutoresizingMaskIntoConstraints = false
        downloadsButton.translatesAutoresizingMaskIntoConstraints = false
        documentsButton.translatesAutoresizingMaskIntoConstraints = false
        terminalButton.translatesAutoresizingMaskIntoConstraints = false
        ftpButton.translatesAutoresizingMaskIntoConstraints = false
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
            terminalButton.trailingAnchor.constraint(equalTo: ftpButton.leadingAnchor, constant: -8),
            terminalButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            ftpButton.trailingAnchor.constraint(equalTo: syncButton.leadingAnchor, constant: -8),
            ftpButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            syncButton.trailingAnchor.constraint(equalTo: toolbarButton.leadingAnchor, constant: -8),
            syncButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            toolbarButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            toolbarButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])
    }

    private func buildStatusBar() {
        statusBar.wantsLayer = true
        let label = NSTextField(labelWithString: "Tab switch pane   Cmd+D bookmarks   Enter open   Backspace delete   Space preview/select   Opt+Space size")
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

    @objc private func showFTPMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let add = NSMenuItem(title: "Add FTP Connection", action: #selector(addFTPConnectionFromMenu), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        let edit = NSMenuItem(title: "Edit FTP Connections", action: #selector(editFTPConnectionsFromMenu), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        let importXML = NSMenuItem(title: "Import FileZilla XML", action: #selector(importFTPConnectionsFromFileZilla), keyEquivalent: "")
        importXML.target = self
        menu.addItem(importXML)

        let connections = FTPConnectionStore.shared.connections()
        if !connections.isEmpty {
            menu.addItem(.separator())
            for connection in connections {
                let item = NSMenuItem(title: connection.displayName, action: #selector(openFTPConnectionFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = connection.id.uuidString
                item.image = menuSymbol(named: "network")
                menu.addItem(item)
            }
        }

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
    @objc private func addFTPConnectionFromMenu() {
        showFTPManager(select: nil, createNew: true)
    }
    @objc private func editFTPConnectionsFromMenu() {
        showFTPManager(select: FTPConnectionStore.shared.connections().first?.id, createNew: false)
    }
    @objc private func importFTPConnectionsFromFileZilla() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.xml]
        panel.title = "Import FileZilla XML"

        panel.beginSheetModal(for: self) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let imported = try FileZillaImport.loadConnections(from: url)
                guard !imported.isEmpty else {
                    self.presentInfoAlert(title: "No FTP Connections Found", message: "The selected XML does not contain any FileZilla server entries.")
                    return
                }

                for connection in imported {
                    FTPConnectionStore.shared.upsert(connection)
                }

                let ftpOnly = imported.filter { $0.protocolType == 0 }.count
                let otherProtocols = imported.count - ftpOnly
                var message = "Imported \(imported.count) connection(s)."
                if otherProtocols > 0 {
                    message += " \(otherProtocols) use a non-FTP protocol and may need a later implementation before they can open."
                }
                self.presentInfoAlert(title: "Import Complete", message: message)
            } catch {
                self.presentInfoAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }
    @objc private func openFTPConnectionFromMenu(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let connection = FTPConnectionStore.shared.connections().first(where: { $0.id == id }) else { return }
        connectFTP(connection)
    }
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

    private func presentFTPConnectionEditor(connection: FTPConnection?) {
        let alert = NSAlert()
        alert.messageText = connection == nil ? "Add FTP Connection" : "Edit FTP Connection"

        let nameField = NSTextField(string: connection?.name ?? "")
        let hostField = NSTextField(string: connection?.host ?? "")
        let portField = NSTextField(string: "\(connection?.port ?? 21)")
        let userField = NSTextField(string: connection?.username ?? "")
        let passwordField = NSSecureTextField(string: connection?.password ?? "")
        let pathField = NSTextField(string: connection?.initialPath ?? "/")
        let commentsField = NSTextField(string: connection?.comments ?? "")

        let protocolPopup = NSPopUpButton()
        protocolPopup.addItems(withTitles: ["FTP", "SFTP", "FTPS (Implicit)", "FTPS (Explicit)"])
        protocolPopup.selectItem(at: max(0, min(connection?.protocolType ?? 0, protocolPopup.numberOfItems - 1)))

        let logonPopup = NSPopUpButton()
        logonPopup.addItems(withTitles: ["Normal", "Ask Password", "Interactive", "Account", "Key File"])
        let storedLogonType = connection?.logonType ?? 0
        let logonIndex = [0, 1, 2, 3, 4].contains(storedLogonType) ? storedLogonType : 0
        logonPopup.selectItem(at: logonIndex)

        let passivePopup = NSPopUpButton()
        let passiveModes = ["MODE_DEFAULT", "MODE_ACTIVE", "MODE_PASSIVE"]
        passivePopup.addItems(withTitles: ["Default", "Active", "Passive"])
        let passiveIndex = max(0, passiveModes.firstIndex(of: connection?.passiveMode ?? "MODE_DEFAULT") ?? 0)
        passivePopup.selectItem(at: passiveIndex)

        let encodingField = NSTextField(string: connection?.encodingType ?? "Auto")

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name"), nameField],
            [NSTextField(labelWithString: "Server"), hostField],
            [NSTextField(labelWithString: "Port"), portField],
            [NSTextField(labelWithString: "Protocol"), protocolPopup],
            [NSTextField(labelWithString: "Login Type"), logonPopup],
            [NSTextField(labelWithString: "User"), userField],
            [NSTextField(labelWithString: "Password"), passwordField],
            [NSTextField(labelWithString: "Remote Path"), pathField],
            [NSTextField(labelWithString: "Passive Mode"), passivePopup],
            [NSTextField(labelWithString: "Encoding"), encodingField],
            [NSTextField(labelWithString: "Comments"), commentsField]
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        (0..<grid.numberOfRows).forEach { row in
            grid.cell(atColumnIndex: 1, rowIndex: row).contentView?.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }

        alert.accessoryView = grid
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: self) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = Int(portField.stringValue) ?? 21
            let user = userField.stringValue
            let password = passwordField.stringValue
            let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let comments = commentsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let protocolType = protocolPopup.indexOfSelectedItem
            let logonType = logonPopup.indexOfSelectedItem
            let passiveMode = passiveModes[max(0, passivePopup.indexOfSelectedItem)]
            let encodingType = encodingField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return }
            FTPConnectionStore.shared.upsert(
                FTPConnection(
                    id: connection?.id ?? UUID(),
                    name: name,
                    host: host,
                    port: port,
                    username: user,
                    password: password,
                    initialPath: path.isEmpty ? "/" : path,
                    comments: comments,
                    protocolType: protocolType,
                    logonType: logonType,
                    passiveMode: passiveMode,
                    encodingType: encodingType.isEmpty ? "Auto" : encodingType
                )
            )
        }
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self)
    }

    private func promptForFTPPassword(connection: FTPConnection) {
        let alert = NSAlert()
        alert.messageText = "FTP Password"
        alert.informativeText = "Enter password for \(connection.displayName)"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { response in
            guard response == .alertFirstButtonReturn else { return }
            var updated = connection
            updated.password = field.stringValue
            self.activePanel.navigate(to: updated)
        }
    }

    private func showFTPManager(select connectionID: UUID?, createNew: Bool) {
        if ftpManager == nil {
            ftpManager = FTPConnectionManagerWindowController()
            ftpManager?.onConnect = { [weak self] connection in
                self?.connectFTP(connection)
            }
        }
        ftpManager?.show(select: connectionID)
        if createNew {
            ftpManager?.openNewConnection()
        }
    }

    private func presentFTPEditorList() {
        let alert = NSAlert()
        alert.messageText = "Edit FTP Connections"

        let connections = FTPConnectionStore.shared.connections()
        guard !connections.isEmpty else {
            presentInfoAlert(title: "No FTP Connections", message: "There are no saved FTP connections to edit yet.")
            return
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        popup.addItems(withTitles: connections.map(\.displayName))
        popup.translatesAutoresizingMaskIntoConstraints = false
        alert.accessoryView = popup
        alert.addButton(withTitle: "Edit")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Close")

        alert.beginSheetModal(for: self) { response in
            let selected = connections[max(0, popup.indexOfSelectedItem)]
            if response == .alertFirstButtonReturn {
                self.presentFTPConnectionEditor(connection: selected)
            } else if response == .alertSecondButtonReturn {
                FTPConnectionStore.shared.remove(id: selected.id)
            }
        }
    }

    private func applyTheme() {
        let palette = currentPalette
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = palette.windowBackground.cgColor
        topBar.layer?.backgroundColor = palette.headerBackground.cgColor
        statusBar.layer?.backgroundColor = palette.headerBackground.cgColor
        functionBar.layer?.backgroundColor = palette.footerBackground.cgColor
        divider.layer?.backgroundColor = palette.border.cgColor
        favoritesButton.contentTintColor = palette.primaryText
        downloadsButton.contentTintColor = palette.primaryText
        documentsButton.contentTintColor = palette.primaryText
        locationsButton.contentTintColor = palette.primaryText
        terminalButton.contentTintColor = palette.primaryText
        ftpButton.contentTintColor = palette.primaryText
        syncButton.contentTintColor = palette.primaryText
        toolbarButton.contentTintColor = palette.primaryText
        for subview in statusBar.subviews {
            (subview as? NSTextField)?.textColor = palette.secondaryText
        }
        leftPanel.applyTheme()
        rightPanel.applyTheme()
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

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItems[index]
    }
}
