import SwiftUI

struct InspectorView: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Crop", systemImage: "crop")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Reset Selection", systemImage: "arrow.counterclockwise") { model.resetSelection() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help("Reset Selection").disabled(model.source == nil)
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
                    Label(model.confirmedCrop == nil ? "Confirm Selection" : "Edit Selection",
                          systemImage: model.confirmedCrop == nil ? "checkmark" : "crop")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.confirmedCrop == nil && !model.canConfirm)
                .help(model.confirmedCrop == nil ? "Confirm Selection and Crop (⌘K)" : "Return to Original Image to Adjust Selection")
                Button { model.export() } label: {
                    HStack(spacing: 8) {
                        if model.isExporting { ProgressView().controlSize(.small) }
                        else { Image(systemName: "square.and.arrow.up") }
                        Text(model.isExporting ? "Exporting" : "Export Image")
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
            Text("Selection Aspect Ratio").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                Picker("Selection Aspect Ratio", selection: Binding(get: { model.settings.preset }, set: { model.setPreset($0) })) {
                    ForEach(AspectPreset.allCases) { preset in Text(preset.title).tag(preset) }
                }
                .labelsHidden()
                Button("Swap Width and Height", systemImage: "arrow.left.arrow.right") { model.swapRatio() }
                    .labelStyle(.iconOnly).help("Swap Aspect Ratio")
            }
            HStack(spacing: 10) {
                TextField("Aspect Ratio Width", value: Binding(get: { model.settings.ratioWidth }, set: { model.setRatio($0, isWidth: true) }),
                          format: .number.grouping(.never).precision(.fractionLength(0...3)))
                    .accessibilityLabel("Aspect Ratio Width")
                Text(":").foregroundStyle(.secondary)
                TextField("Aspect Ratio Height", value: Binding(get: { model.settings.ratioHeight }, set: { model.setRatio($0, isWidth: false) }),
                          format: .number.grouping(.never).precision(.fractionLength(0...3)))
                    .accessibilityLabel("Aspect Ratio Height")
            }
            .textFieldStyle(.roundedBorder)
            if model.source != nil {
                HStack {
                    Text(model.confirmedCrop == nil ? "Current Selection" : "Confirmed Selection")
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
                Text("Output Resolution").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Width").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Width", value: Binding(get: { model.settings.outputWidth }, set: { model.setDimension($0, isWidth: true) }), format: .number.grouping(.never))
                        .accessibilityLabel("Output Width")
                }
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Height").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Height", value: Binding(get: { model.settings.outputHeight }, set: { model.setDimension($0, isWidth: false) }), format: .number.grouping(.never))
                        .accessibilityLabel("Output Height")
                }
            }
            .textFieldStyle(.roundedBorder)
            if !model.settings.validOutput {
                Text("Output must not exceed 100 million pixels or 16,384 pixels on either side.")
                    .font(.system(size: 11)).foregroundStyle(.red)
            } else if model.source != nil && (Double(model.settings.outputWidth) > model.selection.width || Double(model.settings.outputHeight) > model.selection.height) {
                Label("Output Will Enlarge the Selection", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Format").font(.system(size: 12, weight: .semibold))
            Picker("Export Format", selection: Binding(get: { model.settings.format }, set: { model.settings.format = $0 })) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.title).tag(format).disabled(!format.isAvailable)
                }
            }
            .labelsHidden()
            if model.settings.format.supportsQuality {
                HStack {
                    Text("Quality")
                    Spacer()
                    Text(model.settings.quality, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.settings.quality }, set: { model.settings.quality = $0 }), in: 0.01...1, step: 0.01)
                    .accessibilityLabel("Export Quality")
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Location").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.settings.directoryPath.isEmpty ? String(localized: "No Folder Selected") : URL(fileURLWithPath: model.settings.directoryPath).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                    .help(model.settings.directoryPath)
                Spacer(minLength: 0)
                Button("Choose Folder", systemImage: "ellipsis") { model.chooseDirectory() }
                    .labelStyle(.iconOnly).help("Choose Export Folder")
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
