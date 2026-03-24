import AppKit
import Foundation

struct FileItem {
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy HH:mm"
        return formatter
    }()

    var name: String
    var url: URL
    var isDirectory: Bool
    var typeDescription: String
    var size: Int64
    var modDate: Date
    var isMarked: Bool = false
    let isParent: Bool
    let isVirtual: Bool

    var displayName: String { isParent ? ".." : (isDirectory ? "[\(name)]" : name) }

    var displaySize: String {
        if isParent { return "" }
        if isDirectory { return "<DIR>" }
        return FileItem.formatSize(size)
    }

    var displayType: String {
        if isParent { return "" }
        return typeDescription
    }

    var displayDate: String {
        if isParent || isVirtual { return "" }
        return Self.displayDateFormatter.string(from: modDate)
    }

    static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return "\(bytes / 1_024) KB" }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }
}

final class ZipArchiveBrowser {
    let archiveURL: URL
    private let allPaths: [String]

    init(archiveURL: URL) throws {
        self.archiveURL = archiveURL
        self.allPaths = try FileOps.listZipArchive(archiveURL)
    }

    func items(at prefix: String) -> [FileItem] {
        var result: [FileItem] = []
        if !prefix.isEmpty {
            result.append(FileItem(name: "..", url: archiveURL, isDirectory: true, typeDescription: "", size: 0, modDate: .now, isParent: true, isVirtual: true))
        }

        let normalized = prefix.isEmpty ? "" : "\(prefix)/"
        var dirs = Set<String>()
        var files: [FileItem] = []

        for rawPath in allPaths where rawPath.hasPrefix(normalized) {
            let remainder = String(rawPath.dropFirst(normalized.count))
            guard !remainder.isEmpty else { continue }
            if let slash = remainder.firstIndex(of: "/") {
                dirs.insert(String(remainder[..<slash]))
            } else if !rawPath.hasSuffix("/") {
                files.append(FileItem(name: remainder, url: archiveURL, isDirectory: false, typeDescription: "File", size: 0, modDate: .now, isParent: false, isVirtual: true))
            }
        }

        let dirItems = dirs.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { FileItem(name: $0, url: archiveURL, isDirectory: true, typeDescription: "Folder", size: 0, modDate: .now, isParent: false, isVirtual: true) }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result + dirItems + files
    }
}

private enum SortField: String {
    case name
    case type
    case size
    case date
}

final class PaneTableView: NSTableView {
    weak var owner: FilePanel?
    private var rightDragMarkValue: Bool?
    private var rightDragLastRow: Int?
    private var rightDragVisitedRows = IndexSet()

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isDeleteEvent(event) {
            owner?.requestDelete(permanently: isPermanentDeleteEvent(event))
            return true
        }
        if isInspectEvent(event) {
            owner?.showSpaceInfo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isDeleteEvent(event) {
            owner?.requestDelete(permanently: isPermanentDeleteEvent(event))
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            switch event.keyCode {
            case 125:
                owner?.markAndMove(delta: 1)
                return
            case 126:
                owner?.markAndMove(delta: -1)
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 36, 76:
            owner?.openCurrent()
        case 115:
            owner?.moveToStart()
        case 119:
            owner?.moveToEnd()
        case 116:
            owner?.movePage(delta: -1)
        case 121:
            owner?.movePage(delta: 1)
        case 51:
            owner?.requestDelete()
        case 49:
            if flags.contains(.option) {
                owner?.showSpaceInfo()
            } else {
                owner?.handleSpaceAction()
            }
        case 114:
            owner?.toggleMarkCurrent()
        default:
            if event.charactersIgnoringModifiers == "+" {
                owner?.selectByPatternPrompt()
                return
            }
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else {
            super.rightMouseDown(with: event)
            return
        }

        let shouldMark = !(owner?.isMarked(at: row) ?? false)
        rightDragMarkValue = shouldMark
        rightDragLastRow = row
        rightDragVisitedRows = IndexSet(integer: row)
        owner?.handleRightClick(on: row, marked: shouldMark)
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let markValue = rightDragMarkValue else {
            super.rightMouseDragged(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return }

        let start = min(rightDragLastRow ?? row, row)
        let end = max(rightDragLastRow ?? row, row)
        for index in start...end where !rightDragVisitedRows.contains(index) {
            rightDragVisitedRows.insert(index)
            owner?.handleRightClick(on: index, marked: markValue)
        }
        rightDragLastRow = row
    }

    override func rightMouseUp(with event: NSEvent) {
        rightDragMarkValue = nil
        rightDragLastRow = nil
        rightDragVisitedRows.removeAll()
        super.rightMouseUp(with: event)
    }

    override func deleteForward(_ sender: Any?) {
        owner?.requestDelete()
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(deleteForward(_:)) {
            owner?.requestDelete()
            return
        }
        super.doCommand(by: selector)
    }

    private func isDeleteEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 117
    }

    private func isPermanentDeleteEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
    }

    private func isInspectEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 49 && flags.contains(.option)
    }
}

final class PaneRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard let tableView = superview as? PaneTableView,
              let owner = tableView.owner else {
            super.drawSelection(in: dirtyRect)
            return
        }
        let palette = owner.currentPalette
        (owner.isPanelActive ? palette.cursor : palette.inactiveCursor).setFill()
        dirtyRect.fill()
    }

    override var isEmphasized: Bool { get { false } set {} }
}

final class NameCellView: NSTableCellView {
    let iconView = NSImageView()
    let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(iconView)
        addSubview(titleField)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingMiddle
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class CapacityBarView: NSView {
    var usedFraction: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 3)
        let background = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.underPageBackgroundColor.setFill()
        background.fill()

        let fraction = max(0, min(1, usedFraction))
        let width = rect.width * fraction
        if width > 0 {
            let usedRect = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            let color: NSColor = fraction < 0.65 ? .systemGreen : (fraction < 0.85 ? .systemOrange : .systemRed)
            let used = NSBezierPath(roundedRect: usedRect, xRadius: 4, yRadius: 4)
            color.setFill()
            used.fill()
        }

        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()
    }
}

final class BreadcrumbBarView: NSScrollView {
    final class Button: NSButton {
        var targetURL: URL?
        var actionString: String?
    }

    private let stack = NSStackView()
    private var buttons: [Button] = []
    private var arrows: [NSTextField] = []
    var onSelect: ((URL) -> Void)?
    var onSelectFTPPath: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        let document = NSView()
        document.addSubview(stack)
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: document.heightAnchor)
        ])
        documentView = document
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPath(_ url: URL) {
        setSegments(url.standardizedFileURL.pathComponents.enumerated().map { index, component in
            let target: URL = {
                var current = URL(fileURLWithPath: "/")
                if index > 0 {
                    for next in url.standardizedFileURL.pathComponents[1...index] {
                        current.appendPathComponent(next)
                    }
                }
                return current
            }()
            return (component == "/" ? "/" : component, target, nil)
        })
    }

    func setFTPSegments(connection: FTPConnection, path: String) {
        var segments: [(String, URL?, String?)] = [(connection.displayName, nil, "/")]
        let components = URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
        var current = "/"
        for component in components {
            current = FTPBrowser.childPath(parent: current, child: component)
            segments.append((component, nil, current))
        }
        setSegments(segments)
    }

    private func setSegments(_ segments: [(String, URL?, String?)]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buttons.removeAll()
        arrows.removeAll()

        for (index, segment) in segments.enumerated() {
            let button = Button(title: segment.0, target: self, action: #selector(click(_:)))
            button.targetURL = segment.1
            button.actionString = segment.2
            button.isBordered = false
            button.bezelStyle = .inline
            button.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            button.imagePosition = .imageLeft
            stack.addArrangedSubview(button)
            buttons.append(button)
            if index < segments.count - 1 {
                let arrow = NSTextField(labelWithString: "›")
                arrow.font = NSFont.systemFont(ofSize: 10, weight: .medium)
                arrow.textColor = NSColor.secondaryLabelColor
                stack.addArrangedSubview(arrow)
                arrows.append(arrow)
            }
        }
    }

    func applyTheme(_ palette: Palette) {
        wantsLayer = true
        layer?.backgroundColor = palette.headerBackground.cgColor
        layer?.cornerRadius = 6
        buttons.forEach {
            $0.contentTintColor = palette.primaryText
            let title = NSAttributedString(
                string: $0.title,
                attributes: [
                    .foregroundColor: palette.primaryText,
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium)
                ]
            )
            $0.attributedTitle = title
        }
        arrows.forEach { $0.textColor = palette.secondaryText }
    }

    @objc private func click(_ sender: Button) {
        if let url = sender.targetURL {
            onSelect?(url)
        } else if let actionString = sender.actionString {
            onSelectFTPPath?(actionString)
        }
    }
}

final class FilePanel: NSView {
    private weak var hostWindow: MainWindow?
    private(set) var isPanelActive = false
    private(set) var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    private var ftpConnection: FTPConnection?
    private var ftpPath = "/"
    private var items: [FileItem] = []
    private var archiveBrowser: ZipArchiveBrowser?
    private var archivePath = ""
    private var pendingSelectionName: String?
    private var remoteLoadGeneration = 0
    private var sortField: SortField = .name
    private var sortAscending = true
    private let iconCache = NSCache<NSString, NSImage>()

    let tableView = PaneTableView()
    private let scrollView = NSScrollView()
    private let headerBreadcrumbBar = BreadcrumbBarView()
    private let infoLabel = NSTextField(labelWithString: "")
    private let capacityLabel = NSTextField(labelWithString: "")
    private let capacityBar = CapacityBarView()
    private let footer = NSView()
    var onLocationChanged: (() -> Void)?
    var currentPalette: Palette { hostWindow?.currentPalette ?? TC.palette(for: nil) }
    var isRemoteConnectionActive: Bool { ftpConnection != nil }
    var remoteConnection: FTPConnection? { ftpConnection }
    var remoteDirectoryPath: String? { ftpConnection == nil ? nil : ftpPath }

    var currentDirectoryForOperations: URL? {
        archiveBrowser == nil && ftpConnection == nil ? currentURL : nil
    }

    var operationItems: [FileItem] {
        guard archiveBrowser == nil else { return [] }
        let marked = items.filter(\.isMarked)
        if !marked.isEmpty { return marked }
        if let currentItem, !currentItem.isParent { return [currentItem] }
        return []
    }

    var currentItem: FileItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    func remotePath(for item: FileItem) -> String? {
        guard ftpConnection != nil, !item.isParent else { return nil }
        return FTPBrowser.childPath(parent: ftpPath, child: item.name)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func attach(to window: MainWindow) {
        hostWindow = window
        headerBreadcrumbBar.onSelect = { [weak self] url in
            self?.navigate(to: url)
        }
        headerBreadcrumbBar.onSelectFTPPath = { [weak self] path in
            self?.navigateFTP(to: path)
        }
    }

    func setPanelActive(_ active: Bool) {
        isPanelActive = active
        let palette = hostWindow?.currentPalette ?? TC.palette(for: nil)
        layer?.borderWidth = 1
        layer?.borderColor = palette.border.cgColor
        tableView.enumerateAvailableRowViews { rowView, _ in
            rowView.needsDisplay = true
        }
    }

    func applyTheme() {
        let palette = hostWindow?.currentPalette ?? TC.palette(for: nil)
        layer?.backgroundColor = palette.panelBackground.cgColor
        layer?.borderColor = palette.border.cgColor
        headerBreadcrumbBar.applyTheme(palette)
        footer.layer?.backgroundColor = palette.footerBackground.cgColor
        tableView.backgroundColor = palette.panelBackground
        tableView.headerView?.layer?.backgroundColor = palette.headerBackground.cgColor
        infoLabel.textColor = palette.secondaryText
        capacityLabel.textColor = palette.secondaryText
        tableView.reloadData()
        tableView.enumerateAvailableRowViews { rowView, _ in
            rowView.needsDisplay = true
        }
    }

    func showBookmarksMenu() {
        guard let window = window else { return }
        let menu = NSMenu(title: "Bookmarks")
        let add = NSMenuItem(title: "Bookmark current folder", action: #selector(addCurrentFolderBookmark), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let bookmarks = BookmarksStore.shared.bookmarks()
        if !bookmarks.isEmpty {
            menu.addItem(.separator())
            for bookmark in bookmarks {
                let item = NSMenuItem(title: bookmark.path, action: #selector(openBookmark(_:)), keyEquivalent: "")
                item.representedObject = bookmark
                item.target = self
                menu.addItem(item)
            }
        }
        let point = convert(bounds.origin, to: nil)
        let inWindow = window.contentView?.convert(point, from: nil) ?? NSPoint(x: 20, y: bounds.maxY - 20)
        menu.popUp(positioning: add, at: inWindow, in: window.contentView)
    }

    @objc func addCurrentFolderBookmark() {
        guard let folder = currentDirectoryForOperations else { return }
        BookmarksStore.shared.add(folder)
    }

    @objc private func openBookmark(_ sender: NSMenuItem) {
        guard let bookmark = sender.representedObject as? URL else { return }
        navigate(to: bookmark)
    }

    @objc private func handleDoubleClick() {
        openCurrent()
    }

    func navigate(to url: URL) {
        navigate(to: url, selectingName: nil)
    }

    func navigate(to url: URL, selectingName: String?) {
        ftpConnection = nil
        ftpPath = "/"
        currentURL = url
        archiveBrowser = nil
        archivePath = ""
        pendingSelectionName = selectingName
        reloadKeepPos(selectingName: selectingName)
    }

    func navigate(to connection: FTPConnection) {
        ftpConnection = connection
        ftpPath = connection.initialPath
        archiveBrowser = nil
        archivePath = ""
        pendingSelectionName = nil
        reloadKeepPos(selectingName: nil)
    }

    func navigateFTP(to path: String) {
        guard ftpConnection != nil else { return }
        ftpPath = path
        reloadKeepPos(selectingName: nil)
    }

    func refreshCurrentLocation() {
        reloadKeepPos(selectingName: currentItem?.name)
    }

    func disconnectRemote() {
        guard ftpConnection != nil else { return }
        let fallback = currentDirectoryForOperations ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        navigate(to: fallback)
    }

    func reloadKeepPos() {
        reloadKeepPos(selectingName: currentItem?.name)
    }

    func reloadKeepPos(selectingName: String?) {
        let selectedName = currentItem?.name
        refreshPath()
        let preferredName = selectingName ?? selectedName

        if let ftpConnection {
            remoteLoadGeneration += 1
            let generation = remoteLoadGeneration
            let path = ftpPath
            infoLabel.stringValue = "Loading remote location..."
            capacityLabel.stringValue = ""
            capacityBar.usedFraction = 0
            items = []
            tableView.reloadData()
            onLocationChanged?()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    let loadedItems = try FTPBrowser.list(connection: ftpConnection, path: path)
                    DispatchQueue.main.async {
                        guard self.remoteLoadGeneration == generation,
                              self.ftpConnection?.id == ftpConnection.id,
                              self.ftpPath == path else { return }
                        self.items = loadedItems
                        self.sortItems()
                        self.finishReload(preferredName: preferredName)
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard self.remoteLoadGeneration == generation else { return }
                        self.items = []
                        self.tableView.reloadData()
                        self.updateFooter()
                        self.onLocationChanged?()
                        self.hostWindow?.presentFTPError(error)
                    }
                }
            }
            return
        }

        loadItems()
        finishReload(preferredName: preferredName)
    }

    func openCurrent() {
        guard let item = currentItem else { return }

        if archiveBrowser != nil {
            if item.isParent {
                goUp()
            } else if item.isDirectory {
                archivePath = archivePath.isEmpty ? item.name : "\(archivePath)/\(item.name)"
                reloadKeepPos()
            }
            return
        }

        if let ftpConnection {
            if item.isParent {
                goUp()
            } else if item.isDirectory {
                ftpPath = FTPBrowser.childPath(parent: ftpPath, child: item.name)
                reloadKeepPos()
            } else {
                do {
                    let localURL = try FTPBrowser.download(connection: ftpConnection, remotePath: FTPBrowser.childPath(parent: ftpPath, child: item.name))
                    NSWorkspace.shared.open(localURL)
                } catch {
                    if let hostWindow {
                        FileOps.presentError(error, window: hostWindow)
                    }
                }
            }
            return
        }

        if item.isParent {
            goUp()
        } else if item.isDirectory {
            navigate(to: item.url)
        } else if item.url.pathExtension.lowercased() == "zip" {
            do {
                archiveBrowser = try ZipArchiveBrowser(archiveURL: item.url)
                archivePath = ""
                reloadKeepPos()
            } catch {
                if let hostWindow {
                    FileOps.presentError(error, window: hostWindow)
                }
            }
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func goUp() {
        if let archiveBrowser {
            if archivePath.isEmpty {
                let archiveName = archiveBrowser.archiveURL.lastPathComponent
                navigate(to: archiveBrowser.archiveURL.deletingLastPathComponent(), selectingName: archiveName)
            } else {
                archivePath = archivePath.split(separator: "/").dropLast().joined(separator: "/")
                reloadKeepPos()
            }
            return
        }

        if ftpConnection != nil {
            let previous = URL(fileURLWithPath: ftpPath).lastPathComponent
            let parent = FTPBrowser.parentPath(of: ftpPath)
            ftpPath = parent
            reloadKeepPos(selectingName: previous)
            return
        }

        guard currentURL.path != "/" else { return }
        let previous = currentURL.lastPathComponent
        navigate(to: currentURL.deletingLastPathComponent(), selectingName: previous)
    }

    func toggleMarkCurrent() {
        let row = tableView.selectedRow
        toggleMark(at: row, advanceCursor: true)
    }

    func handleSpaceAction() {
        guard let item = currentItem else { return }
        if ftpConnection != nil, !item.isParent && !item.isDirectory {
            openCurrent()
        } else if !item.isParent && !item.isDirectory && !item.isVirtual {
            hostWindow?.showQuickLook(for: [item.url])
        } else {
            toggleMarkCurrent()
        }
    }

    func markAndMove(delta: Int) {
        let row = tableView.selectedRow
        guard archiveBrowser == nil, row >= 0, row < items.count else { return }
        toggleMark(at: row, advanceCursor: false)

        let target = row + delta
        if target >= 0, target < items.count {
            selectRow(target)
        }
        updateFooter()
    }

    func toggleMark(at row: Int, advanceCursor: Bool) {
        guard archiveBrowser == nil, row >= 0, row < items.count, !items[row].isParent else { return }
        items[row].isMarked.toggle()
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        if advanceCursor {
            moveCursorDown()
        }
        updateFooter()
    }

    func setMark(at row: Int, marked: Bool) {
        guard archiveBrowser == nil, row >= 0, row < items.count, !items[row].isParent else { return }
        guard items[row].isMarked != marked else { return }
        items[row].isMarked = marked
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        updateFooter()
    }

    func isMarked(at row: Int) -> Bool {
        guard archiveBrowser == nil, row >= 0, row < items.count, !items[row].isParent else { return false }
        return items[row].isMarked
    }

    func handleRightClick(on row: Int, marked: Bool) {
        hostWindow?.setActive(self, focus: false)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        setMark(at: row, marked: marked)
    }

    func requestDelete(permanently: Bool = false) {
        if permanently {
            hostWindow?.deleteSelectedPermanently()
        } else {
            hostWindow?.deleteSelected()
        }
    }

    func showSpaceInfo() {
        guard archiveBrowser == nil, let window = hostWindow else { return }
        FileOps.inspect(items: operationItems, window: window)
    }

    func selectByPatternPrompt() {
        guard archiveBrowser == nil, let window else { return }

        let alert = NSAlert()
        alert.messageText = "Select Files"
        alert.informativeText = "File mask:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = "*.*"
        alert.accessoryView = field
        alert.addButton(withTitle: "Select")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        field.selectText(nil)

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.selectByPattern(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func markAll(_ marked: Bool) {
        guard archiveBrowser == nil else { return }
        for index in items.indices where !items[index].isParent {
            items[index].isMarked = marked
        }
        tableView.reloadData()
        updateFooter()
    }

    func beginRename(defaultDestinationDirectory: URL? = nil, destinationPanelToReload: FilePanel? = nil) {
        guard archiveBrowser == nil, let item = currentItem, !item.isParent, let hostWindow else { return }
        let defaultValue = if let defaultDestinationDirectory {
            defaultDestinationDirectory.appendingPathComponent(item.name).path
        } else {
            item.name
        }

        FileOps.promptText(
            title: "Rename / Move",
            message: "",
            defaultValue: defaultValue,
            confirmTitle: "OK",
            cancelTitle: "Cancel",
            window: hostWindow
        ) { [self] inputValue in
            guard let inputValue else { return }
            let input = inputValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty, input != item.name else { return }
            do {
                let destination = self.resolvedMoveDestination(for: item, input: input)
                guard destination.path != item.url.path else { return }
                let selectName = destination.lastPathComponent
                if destination.deletingLastPathComponent() != self.currentURL && destination.lastPathComponent == item.name {
                    FileOperationEngine.shared.enqueue(
                        kind: .move,
                        items: [item],
                        destination: destination.deletingLastPathComponent(),
                        window: hostWindow
                    ) {
                        self.reloadKeepPos()
                        destinationPanelToReload?.reloadKeepPos(selectingName: selectName)
                    }
                } else {
                    try FileManager.default.moveItem(at: item.url, to: destination)
                    if destination.deletingLastPathComponent() == self.currentURL {
                        self.reloadKeepPos(selectingName: selectName)
                    } else {
                        self.reloadKeepPos()
                    }
                    destinationPanelToReload?.reloadKeepPos(selectingName: selectName)
                }
            } catch {
                FileOps.presentError(error, window: hostWindow)
            }
        }
    }

    private func resolvedMoveDestination(for item: FileItem, input: String) -> URL {
        let baseDirectory = item.url.deletingLastPathComponent()
        let rawTarget: URL

        if input.hasPrefix("/") {
            rawTarget = URL(fileURLWithPath: input)
        } else {
            rawTarget = baseDirectory.appendingPathComponent(input)
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: rawTarget.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return rawTarget.appendingPathComponent(item.name)
        }

        return rawTarget
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = (hostWindow?.currentPalette ?? TC.palette(for: nil)).panelBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (hostWindow?.currentPalette ?? TC.palette(for: nil)).border.cgColor

        headerBreadcrumbBar.wantsLayer = true
        headerBreadcrumbBar.applyTheme(hostWindow?.currentPalette ?? TC.palette(for: nil))

        tableView.owner = self
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView?.wantsLayer = true
        tableView.headerView?.layer?.backgroundColor = (hostWindow?.currentPalette ?? TC.palette(for: nil)).headerBackground.cgColor
        tableView.backgroundColor = (hostWindow?.currentPalette ?? TC.palette(for: nil)).panelBackground
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.allowsColumnReordering = false

        let name = NSTableColumn(identifier: .init("name"))
        name.title = "Name"
        name.minWidth = 180
        name.width = 340
        name.sortDescriptorPrototype = NSSortDescriptor(key: SortField.name.rawValue, ascending: true)
        let type = NSTableColumn(identifier: .init("type"))
        type.title = "Type"
        type.minWidth = 120
        type.width = 140
        type.sortDescriptorPrototype = NSSortDescriptor(key: SortField.type.rawValue, ascending: true)
        let size = NSTableColumn(identifier: .init("size"))
        size.title = "Size"
        size.minWidth = 90
        size.width = 110
        size.sortDescriptorPrototype = NSSortDescriptor(key: SortField.size.rawValue, ascending: true)
        let date = NSTableColumn(identifier: .init("date"))
        date.title = "Modified"
        date.minWidth = 120
        date.width = 150
        date.sortDescriptorPrototype = NSSortDescriptor(key: SortField.date.rawValue, ascending: true)
        tableView.addTableColumn(name)
        tableView.addTableColumn(type)
        tableView.addTableColumn(size)
        tableView.addTableColumn(date)
        tableView.sortDescriptors = [name.sortDescriptorPrototype!]

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        footer.wantsLayer = true
        footer.layer?.backgroundColor = (hostWindow?.currentPalette ?? TC.palette(for: nil)).footerBackground.cgColor
        infoLabel.font = TC.mono
        infoLabel.textColor = (hostWindow?.currentPalette ?? TC.palette(for: nil)).secondaryText
        capacityLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        capacityLabel.textColor = (hostWindow?.currentPalette ?? TC.palette(for: nil)).secondaryText

        addSubview(headerBreadcrumbBar)
        addSubview(scrollView)
        addSubview(footer)
        footer.addSubview(infoLabel)
        footer.addSubview(capacityLabel)
        footer.addSubview(capacityBar)

        [headerBreadcrumbBar, scrollView, footer, infoLabel, capacityLabel, capacityBar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            headerBreadcrumbBar.topAnchor.constraint(equalTo: topAnchor),
            headerBreadcrumbBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBreadcrumbBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBreadcrumbBar.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: headerBreadcrumbBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 40),

            infoLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8),
            infoLabel.topAnchor.constraint(equalTo: footer.topAnchor, constant: 4),
            capacityLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -8),
            capacityLabel.topAnchor.constraint(equalTo: footer.topAnchor, constant: 4),

            capacityBar.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8),
            capacityBar.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -8),
            capacityBar.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 4),
            capacityBar.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    private func loadItems() {
        if let archiveBrowser {
            items = archiveBrowser.items(at: archivePath)
            sortItems()
            return
        }

        var result: [FileItem] = []
        if currentURL.path != "/" {
            result.append(FileItem(name: "..", url: currentURL.deletingLastPathComponent(), isDirectory: true, typeDescription: "", size: 0, modDate: .now, isParent: true, isVirtual: false))
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .localizedTypeDescriptionKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let options: FileManager.DirectoryEnumerationOptions = hostWindow?.viewState.showHiddenFiles == true ? [] : .skipsHiddenFiles
            let contents = try FileManager.default.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: keys, options: options)

            for url in contents {
                let values = try url.resourceValues(forKeys: Set(keys))
                let isDirectory = values.isDirectory ?? false
                let item = FileItem(
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: isDirectory,
                    typeDescription: values.localizedTypeDescription ?? (isDirectory ? "Folder" : ((url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased()) )),
                    size: Int64(values.fileSize ?? 0),
                    modDate: values.contentModificationDate ?? .now,
                    isParent: false,
                    isVirtual: false
                )
                result.append(item)
            }

            items = result
            sortItems()
        } catch {
            items = result
        }
    }

    private func finishReload(preferredName: String?) {
        tableView.reloadData()
        let fallback = max(0, min(tableView.selectedRow, items.count - 1))
        if let preferredName, let index = items.firstIndex(where: { $0.name == preferredName }) {
            selectRow(index)
        } else if !items.isEmpty {
            selectRow(fallback)
        }
        restorePendingSelectionIfNeeded()
        updateFooter()
        onLocationChanged?()
    }

    private func refreshPath() {
        if archiveBrowser != nil {
            headerBreadcrumbBar.isHidden = true
        } else if ftpConnection != nil {
            headerBreadcrumbBar.isHidden = false
            headerBreadcrumbBar.setFTPSegments(connection: ftpConnection!, path: ftpPath)
        } else {
            headerBreadcrumbBar.isHidden = false
            headerBreadcrumbBar.setPath(currentURL)
        }
    }

    var terminalDisplayPath: String {
        if let archiveBrowser {
            return archiveBrowser.archiveURL.path + (archivePath.isEmpty ? "" : "/\(archivePath)")
        }
        return currentURL.path
    }

    private func updateFooter() {
        if archiveBrowser != nil {
            infoLabel.stringValue = "ZIP archive view"
            capacityLabel.stringValue = "Archive"
            capacityBar.usedFraction = 0
            return
        }

        let marked = items.filter(\.isMarked)
        if marked.isEmpty {
            let dirs = items.filter { $0.isDirectory && !$0.isParent }.count
            let files = items.filter { !$0.isDirectory && !$0.isParent }.count
            infoLabel.stringValue = "\(dirs) folders, \(files) files"
        } else {
            let total = marked.reduce(Int64(0)) { $0 + $1.size }
            infoLabel.stringValue = "Selected: \(marked.count) | \(FileItem.formatSize(total))"
        }
        updateCapacityDisplay()
    }

    private func updateCapacityDisplay() {
        guard let values = try? currentURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity,
              total > 0 else {
            capacityLabel.stringValue = ""
            capacityBar.usedFraction = 0
            return
        }
        let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let total64 = Int64(total)
        let used = max(0, total64 - free)
        capacityLabel.stringValue = "Free \(FileItem.formatSize(free)) of \(FileItem.formatSize(total64))"
        capacityBar.usedFraction = Double(used) / Double(total64)
    }

    private func icon(for item: FileItem) -> NSImage? {
        if item.isParent {
            return NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: "Parent")
        }
        if item.isVirtual {
            return item.isDirectory
                ? NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
                : NSImage(systemSymbolName: "doc.fill", accessibilityDescription: "File")
        }
        let key = item.url.path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: item.url.path)
        image.size = NSSize(width: 16, height: 16)
        iconCache.setObject(image, forKey: key)
        return image
    }

    private func selectRow(_ row: Int) {
        guard !items.isEmpty else { return }
        let index = max(0, min(row, items.count - 1))
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    private func moveCursorDown() {
        let current = max(0, tableView.selectedRow)
        let next = current + 1
        if next < items.count {
            selectRow(next)
        }
    }

    func moveToStart() {
        guard !items.isEmpty else { return }
        selectRow(0)
    }

    func moveToEnd() {
        guard !items.isEmpty else { return }
        selectRow(items.count - 1)
    }

    func movePage(delta: Int) {
        guard !items.isEmpty else { return }
        let rowsPerPage = max(1, Int(scrollView.contentSize.height / max(1, tableView.rowHeight)))
        let current = max(0, tableView.selectedRow)
        let target = max(0, min(items.count - 1, current + (delta * rowsPerPage)))
        selectRow(target)
    }

    private func restorePendingSelectionIfNeeded() {
        guard let pendingSelectionName else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let index = self.items.firstIndex(where: { $0.name == pendingSelectionName }) {
                self.selectRow(index)
            }
            self.pendingSelectionName = nil
        }
    }

    private func selectByPattern(_ pattern: String) {
        let normalized = pattern.isEmpty ? "*.*" : pattern
        for index in items.indices where !items[index].isParent {
            if wildcardMatch(items[index].name, pattern: normalized) {
                items[index].isMarked.toggle()
            }
        }
        tableView.reloadData()
        updateFooter()
    }

    private func wildcardMatch(_ text: String, pattern: String) -> Bool {
        if pattern == "*" || pattern == "*.*" {
            return true
        }

        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        let regex = "^\(escaped)$"
        return text.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func sortItems() {
        let parents = items.filter(\.isParent)
        var regular = items.filter { !$0.isParent }
        regular.sort(by: compareItems(_:_:))
        items = parents + regular
    }

    private func compareItems(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }

        let orderedAscending: Bool = {
            switch sortField {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .type:
                let typeCompare = lhs.typeDescription.localizedCaseInsensitiveCompare(rhs.typeDescription)
                if typeCompare != .orderedSame {
                    return typeCompare == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                if lhs.size != rhs.size {
                    return lhs.size < rhs.size
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .date:
                if lhs.modDate != rhs.modDate {
                    return lhs.modDate < rhs.modDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }()

        if lhs.name.caseInsensitiveCompare(rhs.name) == .orderedSame &&
            lhs.typeDescription.caseInsensitiveCompare(rhs.typeDescription) == .orderedSame &&
            lhs.size == rhs.size &&
            lhs.modDate == rhs.modDate {
            return false
        }

        return sortAscending ? orderedAscending : !orderedAscending
    }
}

extension FilePanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let field = SortField(rawValue: key) else {
            return
        }

        sortField = field
        sortAscending = descriptor.ascending
        let selectedName = currentItem?.name
        sortItems()
        tableView.reloadData()
        if let selectedName, let index = items.firstIndex(where: { $0.name == selectedName }) {
            selectRow(index)
        } else if !items.isEmpty {
            selectRow(0)
        }
    }
}

extension FilePanel: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PaneRowView()
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        hostWindow?.setActive(self, focus: false)
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateFooter()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let palette = hostWindow?.currentPalette ?? TC.palette(for: nil)
        let color = item.isMarked ? palette.marked : (item.isDirectory || item.isParent ? palette.primaryText : palette.secondaryText)

        switch tableColumn?.identifier.rawValue {
        case "name":
            let cell = NameCellView()
            cell.titleField.font = TC.mono
            cell.titleField.textColor = color
            cell.titleField.stringValue = item.displayName
            cell.iconView.image = icon(for: item)
            return cell
        case "type":
            let cell = NSTextField(labelWithString: item.displayType)
            cell.font = TC.mono
            cell.textColor = color
            return cell
        case "size":
            let cell = NSTextField(labelWithString: item.displaySize)
            cell.font = TC.mono
            cell.textColor = color
            cell.alignment = .right
            return cell
        case "date":
            let cell = NSTextField(labelWithString: item.displayDate)
            cell.font = TC.mono
            cell.textColor = color
            return cell
        default:
            return nil
        }
    }
}
