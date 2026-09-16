import AppKit

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.29, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let glow = NSGradient(starting: NSColor(calibratedRed: 0.29, green: 0.59, blue: 0.48, alpha: 1), ending: NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.29, alpha: 1))!
glow.draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)), angle: -60)
NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.88, alpha: 1).setFill()
let house = NSBezierPath()
house.move(to: NSPoint(x: 218, y: 508)); house.line(to: NSPoint(x: 512, y: 768)); house.line(to: NSPoint(x: 806, y: 508)); house.line(to: NSPoint(x: 750, y: 448)); house.line(to: NSPoint(x: 716, y: 478)); house.line(to: NSPoint(x: 716, y: 280)); house.curve(to: NSPoint(x: 664, y: 228), controlPoint1: NSPoint(x: 716, y: 248), controlPoint2: NSPoint(x: 696, y: 228)); house.line(to: NSPoint(x: 360, y: 228)); house.curve(to: NSPoint(x: 308, y: 280), controlPoint1: NSPoint(x: 328, y: 228), controlPoint2: NSPoint(x: 308, y: 248)); house.line(to: NSPoint(x: 308, y: 478)); house.line(to: NSPoint(x: 274, y: 448)); house.close(); house.fill()
NSColor(calibratedRed: 0.13, green: 0.39, blue: 0.34, alpha: 1).setFill()
let bubble = NSBezierPath(roundedRect: NSRect(x: 391, y: 349, width: 242, height: 180), xRadius: 58, yRadius: 58); bubble.fill()
let tail = NSBezierPath(); tail.move(to: NSPoint(x: 560, y: 363)); tail.line(to: NSPoint(x: 599, y: 313)); tail.line(to: NSPoint(x: 604, y: 390)); tail.close(); tail.fill()
NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.84, alpha: 1).setFill()
for x in [451, 506, 561] { NSBezierPath(ovalIn: NSRect(x: x, y: 427, width: 19, height: 19)).fill() }
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
