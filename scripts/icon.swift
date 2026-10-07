import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.065, green: 0.09, blue: 0.085, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 205, yRadius: 205).fill()
        let mint = NSColor(calibratedRed: 0.68, green: 0.94, blue: 0.77, alpha: 1)
        mint.withAlphaComponent(0.11).setFill()
        NSBezierPath(ovalIn: NSRect(x: 160, y: 160, width: 704, height: 704)).fill()
        let screen = NSBezierPath(roundedRect: NSRect(x: 240, y: 342, width: 544, height: 384), xRadius: 34, yRadius: 34)
        mint.setStroke(); screen.lineWidth = 20; screen.stroke()
        let base = NSBezierPath(roundedRect: NSRect(x: 183, y: 275, width: 658, height: 22), xRadius: 11, yRadius: 11)
        mint.setFill(); base.fill()
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 557, y: 675)); bolt.line(to: NSPoint(x: 409, y: 516))
        bolt.line(to: NSPoint(x: 504, y: 516)); bolt.line(to: NSPoint(x: 467, y: 396))
        bolt.line(to: NSPoint(x: 622, y: 559)); bolt.line(to: NSPoint(x: 526, y: 559)); bolt.close(); bolt.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
