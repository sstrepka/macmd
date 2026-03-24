import AppKit
import Foundation

enum FileOperationKind {
    case copy
    case move

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        }
    }

    var progressTitle: String {
        switch self {
        case .copy: return "Copying"
        case .move: return "Moving"
        }
    }
}

private struct FileOperationJob {
    let kind: FileOperationKind
    let items: [FileItem]
    let destination: URL
    weak var window: NSWindow?
    let completion: () -> Void
}

private enum ConflictAction {
    case skip
    case overwrite
    case overwriteAll
    case rename(URL)
    case cancel
}

private final class OperationProgressWindowController: NSWindowController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let phaseLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let queueLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    var onPauseToggle: (() -> Void)?
    var onCancel: (() -> Void)?

    init(title: String, queueCount: Int, parentWindow: NSWindow?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 132),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isExcludedFromWindowsMenu = true
        super.init(window: window)
        build(queueCount: queueCount)
        if let parentWindow {
            window.center()
            parentWindow.addChildWindow(window, ordered: .above)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(queueCount: Int) {
        guard let contentView = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        phaseLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        phaseLabel.textColor = .secondaryLabelColor
        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        detailLabel.lineBreakMode = .byTruncatingMiddle
        queueLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        queueLabel.textColor = .secondaryLabelColor
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1

        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        cancelButton.target = self
        cancelButton.action = #selector(cancelOperationAction(_:))

        let buttons = NSStackView(views: [pauseButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        [titleLabel, phaseLabel, detailLabel, queueLabel, progressBar, buttons].forEach { stack.addArrangedSubview($0) }

        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        updateQueueCount(queueCount)
    }

    func showProgress(title: String, detail: String, current: Int, total: Int) {
        titleLabel.stringValue = title
        phaseLabel.stringValue = "Item \(min(total, current + 1)) of \(max(1, total))"
        detailLabel.stringValue = detail
        progressBar.maxValue = max(1, Double(total))
        progressBar.doubleValue = Double(current)
    }

    func updateQueueCount(_ count: Int) {
        queueLabel.stringValue = count > 0 ? "Queued: \(count)" : "Queued: 0"
    }

    func setPaused(_ paused: Bool) {
        pauseButton.title = paused ? "Resume" : "Pause"
    }

    @objc private func togglePause() {
        onPauseToggle?()
    }

    @objc private func cancelOperationAction(_ sender: Any?) {
        onCancel?()
    }
}

final class FileOperationEngine {
    static let shared = FileOperationEngine()

    private var queue: [FileOperationJob] = []
    private var currentRunner: OperationRunner?

    func enqueue(kind: FileOperationKind, items: [FileItem], destination: URL, window: NSWindow, completion: @escaping () -> Void) {
        guard !items.isEmpty else { return }
        let job = FileOperationJob(kind: kind, items: items, destination: destination, window: window, completion: completion)
        queue.append(job)
        updateQueueCount()
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard currentRunner == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        let runner = OperationRunner(job: job, queuedCountProvider: { [weak self] in
            self?.queue.count ?? 0
        }, onFinish: { [weak self] in
            guard let self else { return }
            self.currentRunner = nil
            self.updateQueueCount()
            self.startNextIfNeeded()
        })
        currentRunner = runner
        updateQueueCount()
        runner.start()
    }

    private func updateQueueCount() {
        currentRunner?.updateQueueCount(queue.count)
    }
}

private final class OperationRunner {
    private let job: FileOperationJob
    private let queuedCountProvider: () -> Int
    private let onFinish: () -> Void
    private let stateLock = NSCondition()
    private var isPaused = false
    private var isCancelled = false
    private var overwriteAll = false
    private let controller: OperationProgressWindowController

    init(job: FileOperationJob, queuedCountProvider: @escaping () -> Int, onFinish: @escaping () -> Void) {
        self.job = job
        self.queuedCountProvider = queuedCountProvider
        self.onFinish = onFinish
        self.controller = OperationProgressWindowController(
            title: job.kind.progressTitle,
            queueCount: queuedCountProvider(),
            parentWindow: job.window
        )
        controller.onPauseToggle = { [weak self] in self?.togglePause() }
        controller.onCancel = { [weak self] in self?.cancel() }
    }

    func start() {
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run()
        }
    }

    func updateQueueCount(_ count: Int) {
        DispatchQueue.main.async {
            self.controller.updateQueueCount(count)
        }
    }

    private func togglePause() {
        stateLock.lock()
        isPaused.toggle()
        let paused = isPaused
        if !isPaused {
            stateLock.broadcast()
        }
        stateLock.unlock()
        DispatchQueue.main.async {
            self.controller.setPaused(paused)
        }
    }

    private func cancel() {
        stateLock.lock()
        isCancelled = true
        stateLock.broadcast()
        stateLock.unlock()
    }

    private func waitIfNeeded() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        while isPaused && !isCancelled {
            stateLock.wait()
        }
        return !isCancelled
    }

    private func wasCancelled() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled
    }

    private func run() {
        var errors: [String] = []
        let total = job.items.count

        for (index, item) in job.items.enumerated() {
            guard waitIfNeeded() else { break }

            DispatchQueue.main.sync {
                self.controller.showProgress(
                    title: "\(self.job.kind.progressTitle) \(index + 1)/\(total)",
                    detail: item.name,
                    current: index,
                    total: total
                )
            }

            do {
                try process(item: item)
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }

            if wasCancelled() {
                break
            }

            DispatchQueue.main.sync {
                self.controller.showProgress(
                    title: "\(self.job.kind.progressTitle) \(index + 1)/\(total)",
                    detail: item.name,
                    current: index + 1,
                    total: total
                )
            }
        }

        DispatchQueue.main.async {
            if let parent = self.job.window {
                parent.removeChildWindow(self.controller.window!)
            }
            self.controller.close()
            self.job.completion()
            if !errors.isEmpty {
                let alert = NSAlert()
                alert.messageText = "\(self.job.kind.title) errors"
                alert.informativeText = errors.joined(separator: "\n")
                alert.runModal()
            }
            self.onFinish()
        }
    }

    private func process(item: FileItem) throws {
        let source = item.url
        var destination = job.destination.appendingPathComponent(item.name)

        if source.standardizedFileURL == destination.standardizedFileURL {
            return
        }

        while FileManager.default.fileExists(atPath: destination.path) {
            if overwriteAll {
                try removeExistingItem(at: destination)
                break
            }

            let action = resolveConflict(for: item, destination: destination)
            switch action {
            case .skip:
                return
            case .overwrite:
                try removeExistingItem(at: destination)
            case .overwriteAll:
                overwriteAll = true
                try removeExistingItem(at: destination)
            case .rename(let renamedDestination):
                destination = renamedDestination
                continue
            case .cancel:
                cancel()
                return
            }
            break
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch job.kind {
        case .copy:
            try FileManager.default.copyItem(at: source, to: destination)
        case .move:
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    private func removeExistingItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    private func resolveConflict(for item: FileItem, destination: URL) -> ConflictAction {
        let semaphore = DispatchSemaphore(value: 0)
        var result: ConflictAction = .cancel

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Target already exists"
            alert.informativeText = "'\(item.name)' already exists in the destination."
            alert.addButton(withTitle: "Skip")
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Overwrite All")
            alert.addButton(withTitle: "Rename")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                result = .skip
            case .alertSecondButtonReturn:
                result = .overwrite
            case .alertThirdButtonReturn:
                result = .overwriteAll
            case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1):
                result = self.promptRenameDestination(current: destination)
            default:
                result = .cancel
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    private func promptRenameDestination(current: URL) -> ConflictAction {
        let alert = NSAlert()
        alert.messageText = "Rename destination"
        alert.informativeText = "Enter a different destination path."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = current.path
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return .cancel }
        let path = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return .cancel }
        return .rename(URL(fileURLWithPath: path))
    }
}
