import AppKit

/// Escape always selects the dismiss/cancel response, including localized alerts.
final class DialogAlert: NSAlert {
    convenience init(error: Error) {
        self.init()
        let presentation = NSAlert(error: error)
        messageText = presentation.messageText
        informativeText = presentation.informativeText
        alertStyle = presentation.alertStyle
        addButton(withTitle: "OK")
    }

    private func configureEscape() {
        if buttons.isEmpty { addButton(withTitle: "OK") }
        let dismiss = buttons.last!
        dismiss.keyEquivalent = "\u{1b}"
        dismiss.keyEquivalentModifierMask = []
    }

    override func runModal() -> NSApplication.ModalResponse {
        configureEscape()
        return super.runModal()
    }

    override func beginSheetModal(for sheetWindow: NSWindow,
                                 completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        configureEscape()
        super.beginSheetModal(for: sheetWindow, completionHandler: handler)
    }
}

/// Shared Escape handling for custom dialogs, even while a text field is focused.
final class DialogWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else if let parent = sheetParent {
            parent.endSheet(self, returnCode: .cancel)
        } else {
            close()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            cancelOperation(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Cancellation is checked between operations; an in-flight file operation finishes safely.
final class DialogCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
