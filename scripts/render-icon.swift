import AppKit

// Legacy, unmasked RGB fallback. AppIcon.icon is the layered source of truth;
// Xcode 26 uses it directly. This renderer shares its editable SVG layers.
let sourceDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Homem/Resources/AppIcon.icon/Assets")
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/render-icon.swift <output.png>")
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
for name in ["Memoh Sunset.svg", "Handset.svg", "Memoh Face.svg"] {
    guard let layer = NSImage(contentsOf: sourceDirectory.appendingPathComponent(name)) else {
        fatalError("Cannot load icon layer: \(name)")
    }
    layer.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1)
}
NSGraphicsContext.restoreGraphicsState()
// App Store marketing icons must not contain an alpha channel. AppKit draws
// into RGBA; encode the finished opaque pixels as RGB without changing colors.
let rgb = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        let source = bitmap.bitmapData! + y * bitmap.bytesPerRow + x * 4
        precondition(source[3] == 255, "The icon artwork must be fully opaque")
        let destination = rgb.bitmapData! + y * rgb.bytesPerRow + x * 3
        for channel in 0..<3 { destination[channel] = source[channel] }
    }
}
let data = rgb.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
