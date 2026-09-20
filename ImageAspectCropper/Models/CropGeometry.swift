import Foundation
import CoreGraphics

/// All rectangles use the oriented source image's top-left pixel coordinate system.
nonisolated enum CropGeometry {
    static func centered(in size: CGSize, ratio: Double) -> CGRect {
        let width = min(size.width, size.height * ratio)
        let height = width / ratio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    static func moved(_ rect: CGRect, by delta: CGSize, in size: CGSize) -> CGRect {
        CGRect(x: min(max(0, rect.minX + delta.width), size.width - rect.width),
               y: min(max(0, rect.minY + delta.height), size.height - rect.height),
               width: rect.width, height: rect.height)
    }

    static func resized(anchor: CGPoint, pointer: CGPoint, ratio: Double, in size: CGSize) -> CGRect {
        let right = pointer.x >= anchor.x
        let down = pointer.y >= anchor.y
        let availableWidth = right ? size.width - anchor.x : anchor.x
        let availableHeight = down ? size.height - anchor.y : anchor.y
        let desiredWidth = max(abs(pointer.x - anchor.x), abs(pointer.y - anchor.y) * ratio)
        let width = min(max(1, desiredWidth), availableWidth, availableHeight * ratio)
        let height = width / ratio
        return CGRect(x: right ? anchor.x : anchor.x - width,
                      y: down ? anchor.y : anchor.y - height, width: width, height: height)
    }
}
