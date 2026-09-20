import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: EditorViewModel
    @Environment(\.undoManager) private var undoManager
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    ImageCanvas(model: model)
                    if model.source == nil {
                        VStack(spacing: 20) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 46, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.5))
                            Button("打开图片", systemImage: "folder") { model.openImage() }
                                .controlSize(.large)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if model.isLoading {
                        ProgressView().controlSize(.large)
                            .padding(20)
                            .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    model.viewport = size
                    if model.fitsImage { model.fit() }
                }
                statusBar
            }
            Divider()
            InspectorView(model: model)
                .frame(width: 286)
        }
        .frame(minWidth: 840, minHeight: 600)
        .background(.background)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: 3).padding(5).allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            model.load(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .toolbar { editorToolbar }
        .navigationTitle(model.source?.url.lastPathComponent ?? "Image Aspect Cropper")
        .onAppear { model.undoManager = undoManager }
        .alert("无法完成操作", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let source = model.source {
                Image(systemName: model.confirmedCrop == nil ? "photo" : "checkmark.circle.fill")
                    .foregroundStyle(model.confirmedCrop == nil ? Color.secondary : Color.green)
                Text("\(source.pixels.width) × \(source.pixels.height)")
                    .monospacedDigit()
                if !model.status.isEmpty {
                    Divider().frame(height: 12)
                    Text(model.status).lineLimit(1).truncationMode(.middle)
                }
            } else {
                Text("未打开图片")
            }
            Spacer(minLength: 8)
            if let url = model.exportedURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("在 Finder 中显示导出的图片")
            }
            Text(model.source == nil ? "" : "\(Int((model.zoom * 100).rounded()))%")
                .monospacedDigit().frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(.bar)
    }

    @ToolbarContentBuilder private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("打开图片", systemImage: "folder") { model.openImage() }
                .help("打开图片 (⌘O)")
        }
        ToolbarItemGroup(placement: .principal) {
            Picker("工具", selection: $model.tool) {
                Image(systemName: "crop").tag(CanvasTool.crop).help("选区")
                Image(systemName: "hand.draw").tag(CanvasTool.pan).help("平移")
            }
            .pickerStyle(.segmented).frame(width: 82)
            .disabled(model.source == nil || model.confirmedCrop != nil)
            Toggle(isOn: Binding(get: { model.settings.showsGrid }, set: { model.settings.showsGrid = $0 })) {
                Label("构图网格", systemImage: "grid")
            }
            .toggleStyle(.button)
            .help("显示构图网格")
            .disabled(model.confirmedCrop != nil)
        }
        ToolbarItemGroup(placement: .automatic) {
            Button("缩小", systemImage: "minus.magnifyingglass") { model.setZoom(model.zoom / 1.25) }
                .help("缩小 (⌘−)").disabled(model.source == nil)
            Menu {
                Button("适合窗口") { model.fit() }
                ForEach([25, 50, 100, 200, 400], id: \.self) { value in
                    Button("\(value)%") { model.setZoom(Double(value) / 100) }
                }
            } label: {
                Text("\(Int((model.zoom * 100).rounded()))%")
                    .monospacedDigit().frame(width: 48)
            }
            .help("缩放比例").disabled(model.source == nil)
            Button("放大", systemImage: "plus.magnifyingglass") { model.setZoom(model.zoom * 1.25) }
                .help("放大 (⌘+)").disabled(model.source == nil)
            Button("适合窗口", systemImage: "arrow.up.left.and.arrow.down.right") { model.fit() }
                .help("适合窗口 (⌘0)").disabled(model.source == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("导出", systemImage: "square.and.arrow.up") { model.export() }
                .disabled(!model.canExport)
                .help("导出图片 (⇧⌘E)")
        }
    }
}

#Preview {
    ContentView(model: EditorViewModel())
        .frame(width: 1100, height: 740)
}
