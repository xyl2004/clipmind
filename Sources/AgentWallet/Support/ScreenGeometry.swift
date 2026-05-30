import AppKit

enum ScreenGeometry {
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    static func normalizedAccessibilityRect(_ rect: CGRect) -> CGRect? {
        guard rect.width > 0,
              rect.height > 0,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite else {
            return nil
        }

        if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
            return rect
        }

        for screen in NSScreen.screens {
            let frame = screen.frame
            let converted = CGRect(
                x: rect.minX,
                y: frame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            if frame.intersects(converted) {
                return converted
            }
        }

        return nil
    }
}
