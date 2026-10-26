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

// Original floppy icon supplied by the Total Commander website.
let sourceURL = root.appendingPathComponent("Resources/TotalCommander.ico")
guard let source = NSImage(contentsOf: sourceURL) else {
    fatalError("Missing Total Commander icon: \(sourceURL.path)")
}

func image(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                from: .zero, operation: .sourceOver, fraction: 1)
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
