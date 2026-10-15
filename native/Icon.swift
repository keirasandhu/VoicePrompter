import AppKit
import Foundation
let path = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 215, yRadius: 215).fill()
for (i, width) in [590.0, 460.0, 590.0, 380.0].enumerated() {
    (i == 1 ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.88)).setFill()
    NSBezierPath(roundedRect: NSRect(x: 220, y: 690 - Double(i)*137, width: width, height: 60), xRadius: 30, yRadius: 30).fill()
}
NSColor.systemOrange.setFill()
let pointer = NSBezierPath(); pointer.move(to: NSPoint(x: 125, y: 578)); pointer.line(to: NSPoint(x: 185, y: 548)); pointer.line(to: NSPoint(x: 125, y: 518)); pointer.close(); pointer.fill()
image.unlockFocus()
try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0,y: 0,width: pixels,height: pixels)); NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path).appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
