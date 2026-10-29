import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 194, yRadius: 194)
NSGradient(starting: NSColor(calibratedRed: 0.47, green: 0.45, blue: 0.96, alpha: 1),
           ending: NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.75, alpha: 1))!.draw(in: background, angle: -50)
for (index, width) in [510.0, 365.0, 230.0].enumerated() {
    NSColor.white.withAlphaComponent(index == 0 ? 1 : 0.82).setFill()
    NSBezierPath(roundedRect: NSRect(x: 245, y: 630 - Double(index) * 155, width: width, height: 78), xRadius: 39, yRadius: 39).fill()
}
NSColor(calibratedRed: 0.5, green: 0.95, blue: 0.83, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 685, y: 320, width: 95, height: 95)).fill()
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
