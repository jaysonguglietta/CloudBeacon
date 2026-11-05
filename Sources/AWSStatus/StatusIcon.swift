import AppKit
import StatusCore

enum StatusIcon {
    // Menu bar template images lose their colors. Draw an original-color image
    // so the status remains visible in both light and dark menu bars.
    static func image(for health: Health) -> NSImage {
        let color = tint(for: health)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let dot = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
            color.setFill(); dot.fill()
            NSColor.black.withAlphaComponent(0.3).setStroke(); dot.lineWidth = 0.75; dot.stroke()
            let mark: String
            switch health {
            case .disruption: mark = "×"
            case .degraded: mark = "!"
            case .resolved, .quiet: mark = "✓"
            case .unknown: mark = "?"
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black]
            let size = (mark as NSString).size(withAttributes: attributes)
            (mark as NSString).draw(at: NSPoint(x: (18 - size.width) / 2, y: (18 - size.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = health.label
        return image
    }
    static func tint(for health: Health) -> NSColor {
        switch health {
        case .disruption: return NSColor(srgbRed: 0.96, green: 0.23, blue: 0.26, alpha: 1)
        case .degraded: return NSColor(srgbRed: 1, green: 0.69, blue: 0.12, alpha: 1)
        case .resolved, .quiet: return NSColor(srgbRed: 0.19, green: 0.82, blue: 0.39, alpha: 1)
        case .unknown: return NSColor(srgbRed: 0.60, green: 0.63, blue: 0.67, alpha: 1)
        }
    }
    static func symbol(for health: Health) -> String {
        switch health {
        case .disruption: return "xmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .resolved, .quiet: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}
