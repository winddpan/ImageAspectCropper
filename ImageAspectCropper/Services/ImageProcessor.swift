import Foundation
import CoreGraphics
import ImageIO

nonisolated struct SourceImage: Sendable {
    let id = UUID()
    let url: URL
    let pixels: CGImage
    var size: CGSize { CGSize(width: pixels.width, height: pixels.height) }
}

nonisolated enum ImageProcessingError: LocalizedError {
    case unreadable, tooLarge, invalidCrop, unsupportedFormat, encodingFailed
    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取这张图片，请选择有效的图片文件。"
        case .tooLarge: "图片尺寸过大。请使用不超过 1 亿像素、边长不超过 32,768 像素的图片。"
        case .invalidCrop: "选区或输出尺寸无效。"
        case .unsupportedFormat: "当前系统不支持所选格式的编码，请选择其他格式。"
        case .encodingFailed: "图片编码失败，请尝试其他格式或较小的输出尺寸。"
        }
    }
}

nonisolated enum ImageProcessor {
    @concurrent static func load(url: URL) async throws -> SourceImage {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ImageProcessingError.unreadable }
        guard width <= 32768, height <= 32768, Double(width) * Double(height) <= 100_000_000 else {
            throw ImageProcessingError.tooLarge
        }
        // Decode at full resolution while applying EXIF orientation exactly once.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessingError.unreadable
        }
        try Task.checkCancellation()
        return SourceImage(url: url, pixels: pixels)
    }

    @concurrent static func encode(source: CGImage, crop: CGRect, width: Int, height: Int,
                                   format: ExportFormat, quality: Double) async throws -> Data {
        try Task.checkCancellation()
        guard width > 0, height > 0, width <= 16384, height <= 16384,
              width * height <= 100_000_000,
              let cropped = source.cropping(to: crop.integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))) else {
            throw ImageProcessingError.invalidCrop
        }
        guard format.isAvailable else { throw ImageProcessingError.unsupportedFormat }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImageProcessingError.encodingFailed
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if format == .jpeg {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
        }
        context.interpolationQuality = .high
        context.draw(cropped, in: bounds)
        guard let output = context.makeImage() else { throw ImageProcessingError.encodingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.identifier as CFString, 1, nil) else {
            throw ImageProcessingError.unsupportedFormat
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if format.supportsQuality {
            // ImageIO's AVIF encoder rejects 1.0 with kCMPhotoError_UnsupportedQuality.
            properties[kCGImageDestinationLossyCompressionQuality] = format == .avif ? min(quality, 0.99) : quality
        }
        CGImageDestinationAddImage(destination, output, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.encodingFailed }
        try Task.checkCancellation()
        return data as Data
    }
}
