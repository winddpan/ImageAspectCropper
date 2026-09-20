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
                Button("Open Image…") { model.openImage() }.keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Button("Export Image") { model.export() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.canExport)
            }
            CommandMenu("Image") {
                Button("Confirm Selection") { model.confirmCrop() }.keyboardShortcut("k").disabled(!model.canConfirm)
                Button("Edit Selection") { model.editCrop() }.disabled(model.confirmedCrop == nil)
                Button("Reset Selection") { model.resetSelection() }.disabled(model.source == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { model.setZoom(model.zoom * 1.25) }.keyboardShortcut("+").disabled(model.source == nil)
                Button("Zoom Out") { model.setZoom(model.zoom / 1.25) }.keyboardShortcut("-").disabled(model.source == nil)
                Button("Fit to Window") { model.fit() }.keyboardShortcut("0").disabled(model.source == nil)
                Button("Actual Size") { model.setZoom(1) }.keyboardShortcut("1").disabled(model.source == nil)
            }
        }
    }
}
