import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = projectDirectory.appendingPathComponent("Resources/DaylineIcon.png")
let outputDirectory = projectDirectory
    .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func render(size: Int) -> Data? {
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
    ) else { return nil }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let scale = CGFloat(size) / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    let background = NSBezierPath(
        roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940),
        xRadius: 224,
        yRadius: 224
    )
    let gradient = NSGradient(colors: [
        NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1),
        NSColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1),
        NSColor(red: 0.19, green: 0.18, blue: 0.51, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -45)

    let outerCircle = NSBezierPath(ovalIn: NSRect(x: 212, y: 212, width: 600, height: 600))
    outerCircle.lineWidth = 64
    NSColor.white.setStroke()
    outerCircle.stroke()

    let innerCircle = NSBezierPath(ovalIn: NSRect(x: 392, y: 392, width: 240, height: 240))
    innerCircle.lineWidth = 50
    innerCircle.stroke()

    let marker = NSBezierPath(ovalIn: NSRect(x: 686, y: 649, width: 112, height: 112))
    NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1).setFill()
    marker.fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = render(size: size) else { continue }
    try data.write(
        to: outputDirectory.appendingPathComponent("AppIcon-\(size).png"),
        options: .atomic
    )
    if size == 1024 {
        try data.write(to: sourceURL, options: .atomic)
    }
}
