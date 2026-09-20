//
//  ImageAspectCropperApp.swift
//  ImageAspectCropper
//
//  Created by winddpan on 2026/9/20.
//

import SwiftUI

@main
struct ImageAspectCropperApp: App {
    @State private var model = EditorViewModel()

    var body: some Scene {
        Window("Image Aspect Cropper", id: "editor") {
            ContentView(model: model)
                .onOpenURL { model.load($0) }
        }
        .defaultSize(width: 1140, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开图片…") { model.openImage() }.keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Button("导出图片") { model.export() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.canExport)
            }
            CommandMenu("图像") {
                Button("确认选区") { model.confirmCrop() }.keyboardShortcut("k").disabled(!model.canConfirm)
                Button("重新编辑选区") { model.editCrop() }.disabled(model.confirmedCrop == nil)
                Button("重置选区") { model.resetSelection() }.disabled(model.source == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("放大") { model.setZoom(model.zoom * 1.25) }.keyboardShortcut("+").disabled(model.source == nil)
                Button("缩小") { model.setZoom(model.zoom / 1.25) }.keyboardShortcut("-").disabled(model.source == nil)
                Button("适合窗口") { model.fit() }.keyboardShortcut("0").disabled(model.source == nil)
                Button("实际大小") { model.setZoom(1) }.keyboardShortcut("1").disabled(model.source == nil)
            }
        }
    }
}
