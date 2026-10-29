import AppKit

/// NSToolbar hosts custom views outside the content view. Convert the button's
/// actual bounds through its hosting window instead of treating toolbar-local
/// coordinates as content-view coordinates during NSMenu tracking.
enum ToolbarMenu {
    static func screenAnchor(below button: NSButton) -> NSPoint? {
        guard let window = button.window else { return nil }
        let boundsInWindow = button.convert(button.bounds, to: nil)
        let boundsOnScreen = window.convertToScreen(boundsInWindow)
        return NSPoint(x: boundsOnScreen.minX, y: boundsOnScreen.minY - 4)
    }

    static func show(_ menu: NSMenu, below button: NSButton) {
        guard let anchor = screenAnchor(below: button) else { return }
        menu.popUp(positioning: nil, at: anchor, in: nil)
    }
}
