import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

for size in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let scale = CGFloat(size) / 1024
    let background = NSBezierPath(
        roundedRect: NSRect(x: 52 * scale, y: 52 * scale, width: 920 * scale, height: 920 * scale),
        xRadius: 220 * scale,
        yRadius: 220 * scale
    )
    NSGradient(
        starting: NSColor(red: 0.216, green: 0.529, blue: 1, alpha: 1),
        ending: NSColor(red: 0.294, green: 0.271, blue: 0.839, alpha: 1)
    )?.draw(in: background, angle: -45)

    NSColor.white.setStroke()
    let frame = NSBezierPath(
        roundedRect: NSRect(x: 190 * scale, y: 264 * scale, width: 644 * scale, height: 496 * scale),
        xRadius: 150 * scale,
        yRadius: 150 * scale
    )
    frame.lineWidth = 54 * scale
    frame.stroke()

    let timeline = NSBezierPath()
    timeline.lineWidth = 54 * scale
    timeline.lineCapStyle = .round
    timeline.move(to: NSPoint(x: 260 * scale, y: 512 * scale))
    timeline.line(to: NSPoint(x: 764 * scale, y: 512 * scale))
    timeline.stroke()

    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 474 * scale, y: 436 * scale, width: 152 * scale, height: 152 * scale)).fill()
    NSColor(red: 0.247, green: 0.4, blue: 0.918, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 520 * scale, y: 482 * scale, width: 60 * scale, height: 60 * scale)).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: outputDirectory.appendingPathComponent("AppIcon-\(size).png"), options: .atomic)
}
