import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, png, avif, heic, tiff

    var id: String { rawValue }
    var title: String { self == .jpeg ? "JPEG" : rawValue.uppercased() }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var supportsQuality: Bool { [.jpeg, .avif, .heic].contains(self) }
    var identifier: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        case .avif: "public.avif"
        case .heic: "public.heic"
        case .tiff: "public.tiff"
        }
    }
    var isAvailable: Bool { (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(identifier) }
}

nonisolated enum AspectPreset: String, CaseIterable, Identifiable, Sendable {
    case square = "1:1", widescreen = "16:9", standard = "4:3", photo = "3:2", portrait = "4:5", custom = "custom"
    var id: String { rawValue }
    var title: String { self == .custom ? String(localized: "Custom") : rawValue }
    var components: (Double, Double)? {
        switch self {
        case .square: (1, 1)
        case .widescreen: (16, 9)
        case .standard: (4, 3)
        case .photo: (3, 2)
        case .portrait: (4, 5)
        case .custom: nil
        }
    }
}

@MainActor @Observable
final class EditorSettings {
    @ObservationIgnored private let defaults: UserDefaults
    var preset: AspectPreset { didSet { persist() } }
    var ratioWidth: Double { didSet { persist() } }
    var ratioHeight: Double { didSet { persist() } }
    var dimensionIsWidth: Bool { didSet { persist() } }
    var dimension: Int { didSet { persist() } }
    var format: ExportFormat { didSet { persist() } }
    var quality: Double { didSet { persist() } }
    var showsGrid: Bool { didSet { persist() } }
    var directoryBookmark: Data? { didSet { persist() } }
    var directoryPath: String { didSet { persist() } }

    var aspectRatio: Double { ratioWidth / ratioHeight }
    var outputWidth: Int { dimensionIsWidth ? dimension : max(1, Int((Double(dimension) * aspectRatio).rounded())) }
    var outputHeight: Int { dimensionIsWidth ? max(1, Int((Double(dimension) / aspectRatio).rounded())) : dimension }
    var validOutput: Bool { outputWidth <= 16384 && outputHeight <= 16384 && outputWidth * outputHeight <= 100_000_000 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let values = defaults.dictionary(forKey: "editor.settings") ?? [:]
        let savedPreset = values["preset"] as? String ?? ""
        // Migrate the legacy localized identifier while keeping display text separate.
        preset = savedPreset == "\u{81EA}\u{5B9A}\u{4E49}" ? .custom : (AspectPreset(rawValue: savedPreset) ?? .square)
        let width = values["ratioWidth"] as? Double ?? 1
        let height = values["ratioHeight"] as? Double ?? 1
        ratioWidth = width.isFinite ? min(1000, max(1, width)) : 1
        ratioHeight = height.isFinite ? min(1000, max(1, height)) : 1
        dimensionIsWidth = values["dimensionIsWidth"] as? Bool ?? true
        dimension = min(16384, max(1, values["dimension"] as? Int ?? 1920))
        format = ExportFormat(rawValue: values["format"] as? String ?? "") ?? .jpeg
        let savedQuality = values["quality"] as? Double ?? 0.9
        quality = savedQuality.isFinite ? min(1, max(0.01, savedQuality)) : 0.9
        showsGrid = values["showsGrid"] as? Bool ?? true
        directoryBookmark = values["directoryBookmark"] as? Data
        directoryPath = values["directoryPath"] as? String ?? ""
    }

    private func persist() {
        var values: [String: Any] = [
            "preset": preset.rawValue, "ratioWidth": ratioWidth, "ratioHeight": ratioHeight,
            "dimensionIsWidth": dimensionIsWidth, "dimension": dimension,
            "format": format.rawValue, "quality": quality, "showsGrid": showsGrid,
            "directoryPath": directoryPath
        ]
        values["directoryBookmark"] = directoryBookmark
        defaults.set(values, forKey: "editor.settings")
    }
}
