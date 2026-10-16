import AppKit
import SwiftUI
import TunerCore

/// Quick presets from the menu bar: one click sets every external screen.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Set all screens for")
        ForEach(UseCase.allCases) { useCase in
            Button {
                Task {
                    await model.quickApply(useCase)
                    showWindow() // the monitor-menu steps are there
                }
            } label: {
                Label(useCase.title, systemImage: useCase.symbol)
            }
        }
        Divider()
        Button("Undo Last Apply") {
            Task { await model.undoLastApply() }
        }
        .disabled(model.lastSnapshot == nil)
        Button("Open Display Tuner") { showWindow() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Display Tuner") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
