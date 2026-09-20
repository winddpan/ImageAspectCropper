import AppKit
import Observation
import UniformTypeIdentifiers

enum CanvasTool: String, CaseIterable, Identifiable {
    case crop, pan
    var id: Self { self }
}

@MainActor @Observable
final class EditorViewModel {
    let settings: EditorSettings
    private(set) var source: SourceImage?
    var selection: CGRect = .zero
    private(set) var confirmedCrop: CGRect?
    private(set) var preview: CGImage?
    var tool: CanvasTool = .crop
    var zoom: Double = 1
    var pan: CGSize = .zero
    var viewport: CGSize = .zero
    var fitsImage = true
    private(set) var isLoading = false
    private(set) var isExporting = false
    var errorMessage: String?
    var status = ""
    private(set) var exportedURL: URL?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    init(settings: EditorSettings = EditorSettings()) { self.settings = settings }

    isolated deinit {
        loadTask?.cancel()
        exportTask?.cancel()
    }

    var displayedImage: CGImage? { preview ?? source?.pixels }
    var canConfirm: Bool { source != nil && confirmedCrop == nil && selection.width >= 1 && selection.height >= 1 && !isLoading }
    var canExport: Bool { confirmedCrop != nil && settings.validOutput && settings.format.isAvailable && !isExporting && !isLoading }
    var outputFilename: String {
        "\(source?.url.deletingPathExtension().lastPathComponent ?? "Image").\(settings.format.fileExtension)"
    }
    var fitScale: Double {
        guard let image = displayedImage, viewport.width > 0, viewport.height > 0 else { return 1 }
        return max(0.001, min((viewport.width - 64) / Double(image.width), (viewport.height - 64) / Double(image.height)))
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "打开图片"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.load(url) }
        }
    }

    @discardableResult func load(_ url: URL) -> Task<Void, Never> {
        loadTask?.cancel()
        isLoading = true
        status = "正在打开 \(url.lastPathComponent)"
        let task = Task { [weak self] in
            do {
                let image = try await ImageProcessor.load(url: url)
                guard let self, !Task.isCancelled else { return }
                source = image
                confirmedCrop = nil
                preview = nil
                selection = CropGeometry.centered(in: image.size, ratio: settings.aspectRatio)
                tool = .crop
                undoManager?.removeAllActions()
                exportedURL = nil
                status = ""
                isLoading = false
                fit()
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                isLoading = false
                status = ""
                errorMessage = error.localizedDescription
            }
        }
        loadTask = task
        return task
    }

    func setPreset(_ preset: AspectPreset) {
        settings.preset = preset
        if let (width, height) = preset.components {
            settings.ratioWidth = width
            settings.ratioHeight = height
            resetSelection()
        }
    }

    func setRatio(_ value: Double, isWidth: Bool) {
        guard value.isFinite, value >= 1, value <= 1000 else { return }
        settings.preset = .custom
        if isWidth { settings.ratioWidth = value } else { settings.ratioHeight = value }
        resetSelection()
    }

    func swapRatio() {
        let width = settings.ratioWidth
        settings.ratioWidth = settings.ratioHeight
        settings.ratioHeight = width
        settings.preset = AspectPreset.allCases.first {
            guard let components = $0.components else { return false }
            return components.0 == settings.ratioWidth && components.1 == settings.ratioHeight
        } ?? .custom
        resetSelection()
    }

    func setDimension(_ value: Int, isWidth: Bool) {
        guard (1...16384).contains(value) else { return }
        settings.dimensionIsWidth = isWidth
        settings.dimension = value
        exportedURL = nil
    }

    func resetSelection() {
        guard let source else { return }
        undoManager?.removeAllActions()
        confirmedCrop = nil
        preview = nil
        selection = CropGeometry.centered(in: source.size, ratio: settings.aspectRatio)
        exportedURL = nil
        status = ""
        fit()
    }

    func finishSelectionChange(from oldRect: CGRect) {
        guard oldRect != selection else { return }
        registerUndo(selection: oldRect, confirmed: nil, name: "调整选区")
        exportedURL = nil
        status = ""
    }

    private func registerUndo(selection rect: CGRect, confirmed: CGRect?, name: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            target.restore(selection: rect, confirmed: confirmed, name: name)
        }
        undoManager?.setActionName(name)
    }

    private func restore(selection rect: CGRect, confirmed: CGRect?, name: String) {
        registerUndo(selection: selection, confirmed: confirmedCrop, name: name)
        selection = rect
        confirmedCrop = confirmed
        preview = confirmed.flatMap { source?.pixels.cropping(to: $0.integral) }
        exportedURL = nil
        status = ""
        fit()
    }

    func confirmCrop() {
        guard canConfirm, let image = source?.pixels,
              let cropped = image.cropping(to: selection.integral) else { return }
        registerUndo(selection: selection, confirmed: nil, name: "裁剪")
        confirmedCrop = selection
        preview = cropped
        status = "选区已确认"
        fit()
    }

    func editCrop() {
        guard confirmedCrop != nil else { return }
        registerUndo(selection: selection, confirmed: confirmedCrop, name: "重新编辑选区")
        confirmedCrop = nil
        preview = nil
        status = ""
        tool = .crop
        fit()
    }

    func fit() {
        fitsImage = true
        zoom = fitScale
        pan = .zero
    }

    func setZoom(_ value: Double) {
        fitsImage = false
        zoom = min(16, max(min(0.01, fitScale), value))
    }

    func chooseDirectory(exportAfterChoosing: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择导出目录"
        if !settings.directoryPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: settings.directoryPath) }
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                settings.directoryBookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                settings.directoryPath = url.path
                if exportAfterChoosing { export() }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func export() {
        guard canExport, let source, let crop = confirmedCrop else { return }
        guard let bookmark = settings.directoryBookmark else {
            chooseDirectory(exportAfterChoosing: true)
            return
        }
        do {
            var stale = false
            let directory = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            let accessed = directory.startAccessingSecurityScopedResource()
            defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
            if stale {
                settings.directoryBookmark = try directory.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            settings.directoryPath = directory.path
            let destination = directory.appendingPathComponent(outputFilename)
            // Also protect originals whose extension differs only in case on APFS.
            let sourcePath = source.url.resolvingSymlinksInPath().standardizedFileURL.path
            let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
            guard sourcePath.caseInsensitiveCompare(destinationPath) != .orderedSame else {
                errorMessage = "导出文件与原图路径相同。请选择其他导出目录，以保留原始图片。"
                return
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                let alert = NSAlert()
                alert.messageText = "替换已有文件？"
                alert.informativeText = destination.lastPathComponent
                alert.addButton(withTitle: "替换")
                alert.addButton(withTitle: "取消")
                guard let window = NSApp.keyWindow else { return }
                // Capture this exact document and settings before presenting the sheet.
                let width = settings.outputWidth, height = settings.outputHeight
                let format = settings.format, quality = settings.quality
                alert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn {
                        self?.writeExport(source: source, crop: crop, destination: destination, directory: directory,
                                          width: width, height: height, format: format, quality: quality)
                    }
                }
            } else {
                writeExport(source: source, crop: crop, destination: destination, directory: directory,
                            width: settings.outputWidth, height: settings.outputHeight, format: settings.format, quality: settings.quality)
            }
        } catch {
            settings.directoryBookmark = nil
            errorMessage = "无法访问上次的导出目录，请重新选择。\n\(error.localizedDescription)"
        }
    }

    private func writeExport(source: SourceImage, crop: CGRect, destination: URL, directory: URL,
                             width: Int, height: Int, format: ExportFormat, quality: Double) {
        guard !isExporting else { return }
        isExporting = true
        status = "正在导出 \(destination.lastPathComponent)"
        exportTask = Task { [weak self] in
            let accessed = directory.startAccessingSecurityScopedResource()
            defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await ImageProcessor.encode(source: source.pixels, crop: crop, width: width, height: height, format: format, quality: quality)
                try Task.checkCancellation()
                try await Self.write(data, to: destination)
                guard let self else { return }
                isExporting = false
                if self.source?.id == source.id {
                    exportedURL = destination
                    status = "已导出 \(destination.lastPathComponent)"
                }
            } catch is CancellationError {
                self?.isExporting = false
            } catch {
                self?.isExporting = false
                self?.status = "导出失败"
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    @concurrent private static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }
}
