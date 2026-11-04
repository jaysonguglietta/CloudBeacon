import AppKit

// Code-native icon: no downloaded images, fonts, or image-generation dependency.
@main struct GenerateIcon {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected iconset output directory") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
                NSColor(srgbRed: 0.055, green: 0.10, blue: 0.18, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 205, yRadius: 205).fill()
                NSColor(srgbRed: 1, green: 0.68, blue: 0.18, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 471, y: 240, width: 82, height: 300), xRadius: 32, yRadius: 32).fill()
                NSBezierPath(ovalIn: NSRect(x: 446, y: 520, width: 132, height: 132)).fill()
                NSColor(srgbRed: 1, green: 0.68, blue: 0.18, alpha: 1).setStroke()
                for radius: CGFloat in [160, 265] {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: NSPoint(x: 512, y: 586), radius: radius, startAngle: 30, endAngle: 150)
                    arc.lineWidth = 38; arc.lineCapStyle = .round; arc.stroke()
                }
                NSColor(srgbRed: 0.22, green: 0.82, blue: 0.49, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: 677, y: 205, width: 112, height: 112)).fill()
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                let output = folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
                try bitmap.representation(using: .png, properties: [:])!.write(to: output)
            }
        }
    }
}
