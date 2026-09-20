import SwiftUI

struct InspectorView: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("裁剪", systemImage: "crop")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("重置选区", systemImage: "arrow.counterclockwise") { model.resetSelection() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help("重置选区").disabled(model.source == nil)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    aspectSection
                    Divider()
                    resolutionSection
                    Divider()
                    formatSection
                    Divider()
                    destinationSection
                }
                .padding(20)
            }
            Divider()
            VStack(spacing: 10) {
                Button {
                    if model.confirmedCrop == nil { model.confirmCrop() } else { model.editCrop() }
                } label: {
                    Label(model.confirmedCrop == nil ? "确认选区" : "重新编辑选区",
                          systemImage: model.confirmedCrop == nil ? "checkmark" : "crop")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.confirmedCrop == nil && !model.canConfirm)
                .help(model.confirmedCrop == nil ? "确认选区并裁剪 (⌘K)" : "返回原图调整选区")
                Button { model.export() } label: {
                    HStack(spacing: 8) {
                        if model.isExporting { ProgressView().controlSize(.small) }
                        else { Image(systemName: "square.and.arrow.up") }
                        Text(model.isExporting ? "正在导出" : "导出图片")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
            }
            .controlSize(.large)
            .padding(20)
        }
        .background(.regularMaterial)
    }

    private var aspectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选区比例").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                Picker("选区比例", selection: Binding(get: { model.settings.preset }, set: { model.setPreset($0) })) {
                    ForEach(AspectPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
                }
                .labelsHidden()
                Button("交换宽高", systemImage: "arrow.left.arrow.right") { model.swapRatio() }
                    .labelStyle(.iconOnly).help("交换宽高比")
            }
            HStack(spacing: 10) {
                TextField("比例宽", value: Binding(get: { model.settings.ratioWidth }, set: { model.setRatio($0, isWidth: true) }),
                          format: .number.grouping(.never).precision(.fractionLength(0...3)))
                    .accessibilityLabel("比例宽")
                Text(":").foregroundStyle(.secondary)
                TextField("比例高", value: Binding(get: { model.settings.ratioHeight }, set: { model.setRatio($0, isWidth: false) }),
                          format: .number.grouping(.never).precision(.fractionLength(0...3)))
                    .accessibilityLabel("比例高")
            }
            .textFieldStyle(.roundedBorder)
            if model.source != nil {
                HStack {
                    Text(model.confirmedCrop == nil ? "当前选区" : "已确认选区")
                    Spacer()
                    Text("\(Int(model.selection.width.rounded())) × \(Int(model.selection.height.rounded()))")
                        .monospacedDigit()
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("输出分辨率").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("宽").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("宽", value: Binding(get: { model.settings.outputWidth }, set: { model.setDimension($0, isWidth: true) }), format: .number.grouping(.never))
                        .accessibilityLabel("输出宽度")
                }
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text("高").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("高", value: Binding(get: { model.settings.outputHeight }, set: { model.setDimension($0, isWidth: false) }), format: .number.grouping(.never))
                        .accessibilityLabel("输出高度")
                }
            }
            .textFieldStyle(.roundedBorder)
            if !model.settings.validOutput {
                Text("输出不能超过 1 亿像素或单边 16,384 像素。")
                    .font(.system(size: 11)).foregroundStyle(.red)
            } else if model.source != nil && (Double(model.settings.outputWidth) > model.selection.width || Double(model.settings.outputHeight) > model.selection.height) {
                Label("输出将放大选区", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出格式").font(.system(size: 12, weight: .semibold))
            Picker("导出格式", selection: Binding(get: { model.settings.format }, set: { model.settings.format = $0 })) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.title).tag(format).disabled(!format.isAvailable)
                }
            }
            .labelsHidden()
            if model.settings.format.supportsQuality {
                HStack {
                    Text("质量")
                    Spacer()
                    Text(model.settings.quality, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.settings.quality }, set: { model.settings.quality = $0 }), in: 0.01...1, step: 0.01)
                    .accessibilityLabel("导出质量")
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出位置").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.settings.directoryPath.isEmpty ? "未选择目录" : URL(fileURLWithPath: model.settings.directoryPath).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                    .help(model.settings.directoryPath)
                Spacer(minLength: 0)
                Button("选择目录", systemImage: "ellipsis") { model.chooseDirectory() }
                    .labelStyle(.iconOnly).help("选择导出目录")
            }
            .font(.system(size: 12))
            if model.source != nil {
                Text(model.outputFilename)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
        }
    }
}
