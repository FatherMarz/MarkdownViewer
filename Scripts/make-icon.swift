#!/usr/bin/env swift
import AppKit

let symbolName = "text.alignleft"
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"

try? FileManager.default.removeItem(atPath: outputDir)
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let targets: [(label: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32),
    ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]

func render(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: px, height: px)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = ctx

    let size = CGFloat(px)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    path.addClip()

    guard let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.38, green: 0.50, blue: 0.72, alpha: 1),
        NSColor(srgbRed: 0.22, green: 0.32, blue: 0.52, alpha: 1),
    ]) else { return nil }
    gradient.draw(in: rect, angle: -90)

    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
    let pointSize = size * 0.55
    let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let color = NSImage.SymbolConfiguration(paletteColors: [.white])
    let combined = base.applying(color)
    guard let colored = symbol.withSymbolConfiguration(combined) else { return nil }

    let s = colored.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
    colored.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)

    return rep.representation(using: .png, properties: [:])
}

for (label, px) in targets {
    guard let data = render(px: px) else {
        FileHandle.standardError.write(Data("failed: \(label)\n".utf8))
        continue
    }
    let url = URL(fileURLWithPath: "\(outputDir)/icon_\(label).png")
    try data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(data.count) bytes)")
}
