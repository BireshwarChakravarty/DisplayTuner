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
            }.disabled(!model.canChange)
        }
        Divider()
        Button("Undo Last Apply") {
            Task { await model.undoLastApply() }
        }
        .disabled(model.lastSnapshot == nil || !model.canChange)
        Button("Open Display Tuner") { showWindow() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Display Tuner") {
            Task {
                if model.confirmation != nil { await model.revertUnconfirmed() }
                NSApp.terminate(nil)
            }
        }.disabled(model.isBusy)
            .keyboardShortcut("q")
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
