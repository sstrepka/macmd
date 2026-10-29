import AppKit
import Foundation

_ = NSApplication.shared
let window = MainWindow()
let site = FTPConnection(name: "Snapshot site", host: "test.invalid", username: "tester", password: "test-only", protocolType: 4)
let second = FTPConnection(name: "Second site", host: "second.invalid", username: "other", password: "second-test-only")
let menu = window.ftpMenuForTesting([site, second])
let sites = menu.items.filter { $0.representedObject is FTPConnection }
precondition(sites.count == 2)
precondition((sites[0].representedObject as? FTPConnection) == site)
var selected: [FTPConnection] = []
window.testFTPSelection = { selected.append($0) }
for item in sites {
    precondition(item.target === window)
    precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
}
precondition(selected.isEmpty, "Selection must wait until menu tracking exits")
let deadline = Date().addingTimeInterval(2)
while selected.count < 2 && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
precondition(selected == [site, second], "Dispatch must use the original complete profiles without looking up saved IDs")

final class FlippedContainer: NSView { override var isFlipped: Bool { true } }
for flipped in [false, true] {
    let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    let container: NSView = flipped ? FlippedContainer(frame: NSRect(x: 60, y: 120, width: 400, height: 100)) : NSView(frame: NSRect(x: 60, y: 120, width: 400, height: 100))
    host.contentView!.addSubview(container)
    let button = NSButton(frame: NSRect(x: 35, y: 20, width: 30, height: 24))
    container.addSubview(button)
    let screenBounds = host.convertToScreen(button.convert(button.bounds, to: nil))
    let anchor = ToolbarMenu.screenAnchor(below: button)!
    precondition(abs(anchor.x - screenBounds.minX) < 0.01)
    precondition(abs(anchor.y - (screenBounds.minY - 4)) < 0.01)
    host.setFrameOrigin(NSPoint(x: 220, y: 180))
    let moved = ToolbarMenu.screenAnchor(below: button)!
    precondition(abs(moved.x - anchor.x - 120) < 0.01 && abs(moved.y - anchor.y - 80) < 0.01)
}
precondition(ToolbarMenu.screenAnchor(below: NSButton()) == nil)
print("PASS: complete server snapshots, real AppKit action dispatch after tracking, anchors in flipped/unflipped views and moved windows")
