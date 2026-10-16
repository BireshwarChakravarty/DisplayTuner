import SwiftUI
import TunerCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                Section("Displays") {
                    ForEach(model.displays) { display in
                        DisplayRow(display: display).tag(display.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .toolbar {
                ToolbarItem {
                    Button {
                        model.refresh()
                    } label: {
                        Label("Rescan Displays", systemImage: "arrow.clockwise")
                    }
                }
            }
        } detail: {
            if let display = model.selectedDisplay {
                DisplayDetailView(display: display)
            } else {
                ContentUnavailableView("No Display Selected", systemImage: "display",
                                       description: Text("Choose a screen on the left."))
            }
        }
        .sheet(item: $model.confirmation) { confirmation in
            ConfirmView(deadline: confirmation.deadline)
        }
    }
}

struct DisplayRow: View {
    let display: DisplayFacts

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name).fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if display.mirrorOf != nil { return "Mirroring" }
        guard let mode = display.currentMode else { return "" }
        return "\(mode.layout.label) · \(mode.refreshLabel)"
    }
}

/// "Keep these display settings?" with a countdown, like System Settings.
struct ConfirmView: View {
    @EnvironmentObject private var model: AppModel
    let deadline: Date

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "display")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Keep these display settings?")
                .font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                Text("Reverting in \(remaining) second\(remaining == 1 ? "" : "s") unless you keep them.")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Button("Revert") {
                    Task { await model.revertUnconfirmed() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Keep Settings") {
                    model.keepChanges()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 380)
    }
}
