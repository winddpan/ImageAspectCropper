import AppKit
import ImageIO
import Testing
@testable import ImageAspectCropper

struct CropGeometryTests {
    @Test(arguments: [1.0, 16.0 / 9, 4.0 / 3, 0.8, 0.001, 1000])
    func centeredSelectionStaysInsideImage(ratio: Double) {
        let size = CGSize(width: 4000, height: 3000)
        let rect = CropGeometry.centered(in: size, ratio: ratio)
        #expect(abs(rect.width / rect.height - ratio) < 0.000001)
        #expect(rect.minX >= 0 && rect.minY >= 0)
        #expect(rect.maxX <= size.width && rect.maxY <= size.height)
        #expect(rect.midX == size.width / 2 && rect.midY == size.height / 2)
    }

    @Test func moveClampsAtImageEdges() {
        let rect = CGRect(x: 100, y: 100, width: 160, height: 90)
        let moved = CropGeometry.moved(rect, by: CGSize(width: -9999, height: 9999), in: CGSize(width: 400, height: 300))
        #expect(moved == CGRect(x: 0, y: 210, width: 160, height: 90))
    }

    @Test(arguments: [CGPoint(x: -400, y: -500), CGPoint(x: 5000, y: 9000), CGPoint(x: -100, y: 9000), CGPoint(x: 9000, y: -100)])
    func resizingPreservesRatioAndBounds(pointer: CGPoint) {
        let size = CGSize(width: 400, height: 300)
        let crop = CropGeometry.resized(anchor: CGPoint(x: 200, y: 150), pointer: pointer, ratio: 16.0 / 9, in: size)
        #expect(abs(crop.width / crop.height - 16.0 / 9) < 0.000001)
        #expect(crop.minX >= 0 && crop.minY >= 0 && crop.maxX <= 400 && crop.maxY <= 300)
    }
}

@MainActor struct EditorTests {
    @Test func dimensionsFollowLastEditedAxisAndSettingsPersist() throws {
        let name = "EditorTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = EditorViewModel(settings: EditorSettings(defaults: defaults))
        model.setPreset(.widescreen)
        model.setDimension(1920, isWidth: true)
        #expect(model.settings.outputHeight == 1080)
        model.setDimension(720, isWidth: false)
        #expect(model.settings.outputWidth == 1280)
        model.setPreset(.standard)
        #expect(model.settings.outputWidth == 960 && model.settings.outputHeight == 720)
        model.settings.format = .avif
        model.settings.quality = 0.73
        model.settings.directoryPath = "/tmp/exports"
        let restored = EditorSettings(defaults: defaults)
        #expect(restored.outputWidth == 960 && restored.outputHeight == 720)
        #expect(restored.format == .avif && restored.quality == 0.73)
        #expect(restored.directoryPath == "/tmp/exports")
        model.setDimension(0, isWidth: true)
        model.setRatio(.infinity, isWidth: true)
        #expect(model.settings.outputWidth == 960)
    }

    @Test func replacingImageResetsCropButPreservesSettingsAndUndoIsReversible() async throws {
        let name = "EditorTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = EditorViewModel(settings: EditorSettings(defaults: defaults))
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try ImageFixtures.quadrants()
        let data = try await ImageProcessor.encode(source: image, crop: CGRect(x: 0, y: 0, width: 80, height: 60), width: 80, height: 60, format: .png, quality: 1)
        try data.write(to: url)
        model.setPreset(.widescreen)
        await model.load(url).value
        let oldID = model.source?.id
        let crop = model.selection
        undo.beginUndoGrouping()
        model.confirmCrop()
        undo.endUndoGrouping()
        #expect(model.confirmedCrop == crop)
        #expect(model.canExport)
        undo.undo()
        #expect(model.confirmedCrop == nil && model.canConfirm)
        undo.redo()
        #expect(model.confirmedCrop == crop)
        await model.load(url).value
        #expect(model.source?.id != oldID)
        #expect(model.confirmedCrop == nil && model.preview == nil)
        #expect(model.settings.preset == .widescreen && model.settings.outputWidth == 1920)
        #expect(undo.canUndo == false)
    }
}

nonisolated enum ImageFixtures {
    static func quadrants() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 30, width: 40, height: 30))
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 1, 0, 1])!)
        context.fill(CGRect(x: 40, y: 30, width: 40, height: 30))
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 1, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        return try #require(context.makeImage())
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }
}

struct ImageProcessorTests {
    @Test(arguments: ExportFormat.allCases, [0.9, 0.99, 1.0])
    func exportedFilesHaveCorrectTypeDimensionsAndCrop(format: ExportFormat, quality: Double) async throws {
        let source = try ImageFixtures.quadrants()
        let data = try await ImageProcessor.encode(source: source, crop: CGRect(x: 0, y: 0, width: 40, height: 30), width: 160, height: 120, format: format, quality: quality)
        let decodedSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(decodedSource) as String? == format.identifier)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(decodedSource, 0, nil))
        #expect(decoded.width == 160 && decoded.height == 120)
        let pixel = try ImageFixtures.pixel(decoded, x: 80, y: 60)
        #expect(pixel[0] > 230 && pixel[1] < 20 && pixel[2] < 20)
    }

    @Test func pngPreservesAlphaAndJPEGFlattensToWhite() async throws {
        let source = try ImageFixtures.quadrants()
        for format in [ExportFormat.png, .jpeg] {
            let data = try await ImageProcessor.encode(source: source, crop: CGRect(x: 40, y: 30, width: 40, height: 30), width: 40, height: 30, format: format, quality: 1)
            let decoder = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
            let pixel = try ImageFixtures.pixel(image, x: 20, y: 15)
            if format == .png { #expect(pixel[3] == 0) }
            else { #expect(pixel[0] > 250 && pixel[1] > 250 && pixel[2] > 250 && pixel[3] == 255) }
        }
    }

    @Test func loadAppliesEXIFOrientation() async throws {
        let source = try ImageFixtures.quadrants()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, source, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let loaded = try await ImageProcessor.load(url: url)
        #expect(loaded.pixels.width == 60 && loaded.pixels.height == 80)
        let pixel = try ImageFixtures.pixel(loaded.pixels, x: 45, y: 20)
        #expect(pixel[0] > 230 && pixel[1] < 20 && pixel[2] < 20)
    }
}
