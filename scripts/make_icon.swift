import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent("Resources/macmd.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func image(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let outer = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.12, dy: size * 0.08), xRadius: size * 0.08, yRadius: size * 0.08)
    NSColor(calibratedRed: 0.13, green: 0.48, blue: 0.98, alpha: 1).setFill()
    outer.fill()

    let shutter = NSBezierPath(rect: NSRect(x: size * 0.24, y: size * 0.58, width: size * 0.52, height: size * 0.18))
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    shutter.fill()

    let label = NSBezierPath(roundedRect: NSRect(x: size * 0.28, y: size * 0.20, width: size * 0.44, height: size * 0.24), xRadius: size * 0.03, yRadius: size * 0.03)
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    label.fill()

    let notch = NSBezierPath(roundedRect: NSRect(x: size * 0.58, y: size * 0.22, width: size * 0.10, height: size * 0.16), xRadius: size * 0.015, yRadius: size * 0.015)
    NSColor(calibratedRed: 0.13, green: 0.48, blue: 0.98, alpha: 1).setFill()
    notch.fill()

    let border = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.12, dy: size * 0.08), xRadius: size * 0.08, yRadius: size * 0.08)
    border.lineWidth = max(2, size * 0.02)
    NSColor(calibratedRed: 0.07, green: 0.31, blue: 0.74, alpha: 1).setStroke()
    border.stroke()

    image.unlockFocus()
    return image
}

for (name, size) in sizes {
    let img = image(size: size)
    guard let data = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: data),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(name)")
    }
    try png.write(to: iconsetURL.appendingPathComponent(name))
}
