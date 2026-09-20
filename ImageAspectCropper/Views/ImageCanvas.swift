import AppKit
import SwiftUI

struct ImageCanvas: NSViewRepresentable {
    var model: EditorViewModel

    func makeNSView(context: Context) -> CropCanvasView { CropCanvasView(model: model) }

    func updateNSView(_ view: CropCanvasView, context: Context) {
        view.image = model.displayedImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        view.selection = model.selection
        view.confirmed = model.confirmedCrop != nil
        view.scale = model.zoom
        view.offset = model.pan
        view.grid = model.settings.showsGrid
        view.currentTool = model.tool
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

final class CropCanvasView: NSView {
    let model: EditorViewModel
    var image: NSImage?
    var selection: CGRect = .zero
    var confirmed = false
    var scale: Double = 1
    var offset: CGSize = .zero
    var grid = true
    var currentTool: CanvasTool = .crop
    private var spacePressed = false
    private var dragStart = CGPoint.zero
    private var originalSelection = CGRect.zero
    private var originalPan = CGSize.zero
    private var dragMode: DragMode?
    private enum DragMode { case move, resize(Int), draw(CGPoint), pan }

    init(model: EditorViewModel) {
        self.model = model
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel("图片裁剪画布")
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var imageRect: CGRect {
        guard let image else { return .zero }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2 + offset.width,
                      y: (bounds.height - size.height) / 2 + offset.height, width: size.width, height: size.height)
    }

    private var selectionRect: CGRect {
        CGRect(x: imageRect.minX + selection.minX * scale, y: imageRect.minY + selection.minY * scale,
               width: selection.width * scale, height: selection.height * scale)
    }

    private var handles: [CGPoint] {
        let r = selectionRect
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY),
                CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.105, alpha: 1).setFill()
        bounds.fill()
        guard let image else { return }
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSColor(white: 0.24, alpha: 1).setFill()
        rect.fill()
        NSColor(white: 0.30, alpha: 1).setFill()
        let visible = rect.intersection(bounds)
        let tile: CGFloat = 12
        if !visible.isNull {
            for row in Int(floor(visible.minY / tile))...Int(ceil(visible.maxY / tile)) {
                for column in Int(floor(visible.minX / tile))...Int(ceil(visible.maxX / tile)) where (row + column).isMultiple(of: 2) {
                    CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile).fill()
                }
            }
        }
        NSGraphicsContext.current?.imageInterpolation = scale > 3 ? .none : .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if !confirmed {
            let crop = selectionRect
            let mask = NSBezierPath(rect: rect)
            mask.appendRect(crop)
            mask.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.58).setFill()
            mask.fill()
            if grid {
                let lines = NSBezierPath()
                for index in 1...2 {
                    let fraction = CGFloat(index) / 3
                    lines.move(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.minY))
                    lines.line(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.maxY))
                    lines.move(to: CGPoint(x: crop.minX, y: crop.minY + crop.height * fraction))
                    lines.line(to: CGPoint(x: crop.maxX, y: crop.minY + crop.height * fraction))
                }
                NSColor.white.withAlphaComponent(0.55).setStroke()
                lines.lineWidth = 0.75
                lines.stroke()
            }
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: crop)
            border.lineWidth = 1
            border.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        if !confirmed {
            for (index, point) in handles.enumerated() {
                let horizontal = index == 1 || index == 5
                let vertical = index == 3 || index == 7
                let size = CGSize(width: horizontal ? 20 : 7, height: vertical ? 20 : 7)
                let handle = NSBezierPath(roundedRect: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                                              width: size.width, height: size.height), xRadius: 2, yRadius: 2)
                NSColor.black.withAlphaComponent(0.65).setStroke()
                handle.lineWidth = 2
                handle.stroke()
                NSColor.white.setFill()
                handle.fill()
            }
        }
    }

    override func resetCursorRects() {
        if currentTool == .pan || confirmed || spacePressed {
            addCursorRect(bounds, cursor: .openHand)
        } else {
            addCursorRect(bounds, cursor: .crosshair)
            addCursorRect(selectionRect.intersection(bounds), cursor: .openHand)
            for (index, point) in handles.enumerated() {
                addCursorRect(CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16),
                              cursor: index == 1 || index == 5 ? .resizeUpDown : index == 3 || index == 7 ? .resizeLeftRight : .crosshair)
            }
        }
    }

    private func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, (point.x - imageRect.minX) / scale), image?.size.width ?? 0),
                y: min(max(0, (point.y - imageRect.minY) / scale), image?.size.height ?? 0))
    }

    override func mouseDown(with event: NSEvent) {
        guard image != nil, !model.isLoading else { return }
        window?.makeFirstResponder(self)
        dragStart = convert(event.locationInWindow, from: nil)
        originalSelection = model.selection
        originalPan = model.pan
        if spacePressed || currentTool == .pan || confirmed {
            dragMode = .pan
            NSCursor.closedHand.set()
        } else if let index = handles.enumerated().min(by: {
            hypot($0.element.x - dragStart.x, $0.element.y - dragStart.y) < hypot($1.element.x - dragStart.x, $1.element.y - dragStart.y)
        }), hypot(index.element.x - dragStart.x, index.element.y - dragStart.y) <= 12 {
            dragMode = .resize(index.offset)
        } else if selectionRect.contains(dragStart) {
            dragMode = .move
            NSCursor.closedHand.set()
        } else if imageRect.contains(dragStart) {
            dragMode = .draw(imagePoint(dragStart))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode, let size = model.source?.size else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: (point.x - dragStart.x) / scale, height: (point.y - dragStart.y) / scale)
        switch dragMode {
        case .pan:
            model.pan = CGSize(width: originalPan.width + point.x - dragStart.x, height: originalPan.height + point.y - dragStart.y)
            clampPan()
        case .move:
            model.selection = CropGeometry.moved(originalSelection, by: delta, in: size)
        case .draw(let anchor):
            model.selection = CropGeometry.resized(anchor: anchor, pointer: imagePoint(point), ratio: model.settings.aspectRatio, in: size)
        case .resize(let index):
            let r = originalSelection
            let ratio = model.settings.aspectRatio
            if index.isMultiple(of: 2) {
                let anchor = CGPoint(x: index == 0 || index == 6 ? r.maxX : r.minX,
                                     y: index == 0 || index == 2 ? r.maxY : r.minY)
                model.selection = CropGeometry.resized(anchor: anchor, pointer: imagePoint(point), ratio: ratio, in: size)
            } else if index == 1 || index == 5 {
                let anchorY = index == 1 ? r.maxY : r.minY
                let height = min(max(1, index == 1 ? anchorY - imagePoint(point).y : imagePoint(point).y - anchorY),
                                 index == 1 ? anchorY : size.height - anchorY, min(r.midX, size.width - r.midX) * 2 / ratio)
                model.selection = CGRect(x: r.midX - height * ratio / 2, y: index == 1 ? anchorY - height : anchorY, width: height * ratio, height: height)
            } else {
                let anchorX = index == 7 ? r.maxX : r.minX
                let width = min(max(1, index == 7 ? anchorX - imagePoint(point).x : imagePoint(point).x - anchorX),
                                index == 7 ? anchorX : size.width - anchorX, min(r.midY, size.height - r.midY) * 2 * ratio)
                model.selection = CGRect(x: index == 7 ? anchorX - width : anchorX, y: r.midY - width / ratio / 2, width: width, height: width / ratio)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let dragMode, case .pan = dragMode { } else if dragMode != nil {
            if model.selection.width < 1 || model.selection.height < 1 { model.selection = originalSelection }
            model.finishSelectionChange(from: originalSelection)
        }
        dragMode = nil
        window?.invalidateCursorRects(for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard image != nil else { return }
        if event.modifierFlags.contains(.command) {
            zoom(to: model.zoom * exp(event.scrollingDeltaY * 0.01), at: convert(event.locationInWindow, from: nil))
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            model.pan.width += event.scrollingDeltaX * multiplier
            model.pan.height += event.scrollingDeltaY * multiplier
            clampPan()
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(to: model.zoom * (1 + event.magnification), at: convert(event.locationInWindow, from: nil))
    }

    override func smartMagnify(with event: NSEvent) {
        if abs(model.zoom - 1) < 0.01 { model.fit() }
        else { zoom(to: 1, at: convert(event.locationInWindow, from: nil)) }
    }

    private func zoom(to value: Double, at point: CGPoint) {
        let oldScale = model.zoom
        model.setZoom(value)
        let factor = model.zoom / oldScale
        model.pan = CGSize(width: (model.pan.width + bounds.midX - point.x) * factor - bounds.midX + point.x,
                           height: (model.pan.height + bounds.midY - point.y) * factor - bounds.midY + point.y)
        clampPan()
    }

    private func clampPan() {
        guard let image else { return }
        let maxX = max(0, (image.size.width * model.zoom - bounds.width) / 2 + 48)
        let maxY = max(0, (image.size.height * model.zoom - bounds.height) / 2 + 48)
        model.pan = CGSize(width: min(maxX, max(-maxX, model.pan.width)), height: min(maxY, max(-maxY, model.pan.height)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            spacePressed = true
            window?.invalidateCursorRects(for: self)
        } else if event.keyCode == 53 {
            if model.confirmedCrop != nil { model.editCrop() }
        } else if [123, 124, 125, 126].contains(event.keyCode), !confirmed, let size = model.source?.size {
            let old = model.selection
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta = CGSize(width: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,
                               height: event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0)
            model.selection = CropGeometry.moved(old, by: delta, in: size)
            model.finishSelectionChange(from: old)
        } else { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spacePressed = false
            window?.invalidateCursorRects(for: self)
        } else { super.keyUp(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        spacePressed = false
        return super.resignFirstResponder()
    }
}
