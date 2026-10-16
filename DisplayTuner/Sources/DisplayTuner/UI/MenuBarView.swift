import AppKit
import SwiftUI
import TunerCore

/// The menu-bar popover: what's on now, one-click presets for every external
/// screen, and quick actions.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var mainDisplay: DisplayFacts? {
        model.displays.first { !$0.isBuiltIn && $0.mirrorOf == nil } ?? model.displays.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "display").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mainDisplay?.name ?? "No display").font(.headline).lineLimit(1)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }

            if let auto = model.autoState {
                Label("Auto: \(auto.useCase.title) for \(auto.appName)", systemImage: "wand.and.stars")
                    .font(.caption).foregroundStyle(.orange)
            }

            Text("Set all screens for").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(UseCase.allCases) { useCase in
                    Button {
                        Task {
                            await model.quickApply(useCase)
                            showWindow() // the monitor checklist is there
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: useCase.symbol).frame(width: 18).foregroundStyle(.tint)
                            Text(useCase.title).font(.callout).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(isCurrent(useCase) ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isCurrent(useCase) ? Color.accentColor : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canChange)
                }
            }

            Divider()
            HStack {
                Button("Undo Last Apply") { Task { await model.undoLastApply() } }
                    .disabled(model.lastSnapshot == nil || !model.canChange)
                Spacer()
                Button("Open Display Tuner") { showWindow() }.keyboardShortcut(",")
            }
            .controlSize(.small)
            HStack {
                Spacer()
                Button("Quit") {
                    Task {
                        if model.confirmation != nil { await model.revertUnconfirmed() }
                        NSApp.terminate(nil)
                    }
                }
                .disabled(model.isBusy).keyboardShortcut("q").controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var statusLine: String {
        guard let display = mainDisplay else { return "" }
        let mode = display.currentMode?.label ?? ""
        return "\(model.useCase(for: display.id).title) · \(mode)"
    }

    private func isCurrent(_ useCase: UseCase) -> Bool {
        mainDisplay.map { model.useCase(for: $0.id) == useCase } ?? false
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
