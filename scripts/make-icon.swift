import AppKit

let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let bounds = NSRect(x: 36, y: 36, width: 952, height: 952)
NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.44, alpha: 1).setFill()
NSBezierPath(roundedRect: bounds, xRadius: 220, yRadius: 220).fill()
// Original geometric keyboard artwork; no third-party image or symbol asset.
NSColor.white.setStroke()
let keyboard = NSBezierPath(roundedRect: NSRect(x: 202, y: 298, width: 620, height: 430), xRadius: 65, yRadius: 65)
keyboard.lineWidth = 28
keyboard.stroke()
NSColor.white.setFill()
for row in 0..<2 {
    for column in 0..<4 {
        NSBezierPath(roundedRect: NSRect(x: 250 + column * 138, y: 510 + row * 108,
            width: 104, height: 68), xRadius: 13, yRadius: 13).fill()
    }
}
NSBezierPath(roundedRect: NSRect(x: 250, y: 360, width: 104, height: 68), xRadius: 13, yRadius: 13).fill()
NSBezierPath(roundedRect: NSRect(x: 388, y: 360, width: 242, height: 68), xRadius: 13, yRadius: 13).fill()
NSBezierPath(roundedRect: NSRect(x: 668, y: 360, width: 104, height: 68), xRadius: 13, yRadius: 13).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
