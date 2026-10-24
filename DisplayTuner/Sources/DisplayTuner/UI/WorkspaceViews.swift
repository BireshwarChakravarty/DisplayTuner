import AppKit
import SwiftUI
import ServiceManagement
import TunerCore

struct SavedPresetsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.savedPresets.isEmpty {
                ContentUnavailableView("No Saved Presets", systemImage: "square.stack.3d.up",
                                       description: Text("Set up a display the way you like it, then choose Save as Preset… from its ⋯ menu."))
            } else {
                List {
                    ForEach(model.savedPresets) { preset in
                        HStack(spacing: 12) {
                            Image(systemName: preset.useCase.symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.headline)
                                Text("\(preset.displayName) · \(preset.useCase.title)")
                                    .font(.callout).foregroundStyle(.secondary)
                                if let mode = preset.mode { Text(mode.label).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Load") { model.loadPreset(preset) }
                                .disabled(model.isBusy || model.confirmation != nil)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Delete", role: .destructive) { model.deletePreset(preset.id) }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { model.deletePreset(model.savedPresets[index].id) }
                    }
                }
            }
        }
        .navigationTitle("Saved Presets")
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.activity.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: "clock",
                                       description: Text("Every change you apply, and its result, is listed here. It stays on this Mac."))
            } else {
                List(model.activity) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(entry.ok ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(entry.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem {
                Button { model.exportDiagnostics() } label: { Label("Export Diagnostics", systemImage: "square.and.arrow.up") }
                    .help("Export a diagnostics report (⇧⌘E)")
            }
        }
    }
}

struct StudioSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AutoSwitchSettings.enabledKey) private var autoSwitch = false
    @AppStorage(AutoSwitchSettings.gamePresetKey) private var gamePreset = UseCase.immersiveGaming.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @ViewState private var loginEnabled = SMAppService.mainApp.status == .enabled
    @ViewState private var error: String?
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) { Text("Match System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    .pickerStyle(.segmented)
            }
            Section("Automatic presets") {
                Toggle("Switch presets when games and editing apps are in front", isOn: Binding(
                    get: { autoSwitch },
                    set: { model.setAutoSwitch(enabled: $0, gamePreset: UseCase(rawValue: gamePreset) ?? .immersiveGaming) }))
                Picker("Games use", selection: Binding(
                    get: { gamePreset },
                    set: { model.setAutoSwitch(enabled: autoSwitch, gamePreset: UseCase(rawValue: $0) ?? .immersiveGaming) })) {
                    Text(UseCase.competitiveGaming.title).tag(UseCase.competitiveGaming.rawValue)
                    Text(UseCase.immersiveGaming.title).tag(UseCase.immersiveGaming.rawValue)
                }.disabled(!autoSwitch)
                Text("Photo Editing for Lightroom, Photoshop, Capture One, Affinity Photo, Pixelmator Pro and DxO. Video Editing for Final Cut Pro, DaVinci Resolve, Premiere Pro and After Effects. Games are recognised by their App Store category or Steam library. Leaving them returns your screens to your own preset. Resolution and refresh rate never change automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open Gamut Pro at login", isOn: Binding(get: { loginEnabled }, set: { value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginEnabled = SMAppService.mainApp.status == .enabled
                        error = nil
                        if SMAppService.mainApp.status == .requiresApproval { error = "Approve Gamut Pro in System Settings → General → Login Items." }
                    } catch { self.error = error.localizedDescription }
                }))
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("About Gamut Pro") {
                HStack(spacing: 14) { AppMark().frame(width: 50, height: 50); VStack(alignment: .leading, spacing: 4) { Text("Gamut Pro \(AppVersion.current)").font(.headline); Text("Researched settings for the Acer Nitro XV272K V5.").foregroundStyle(.secondary) } }
                Link("Source, updates & releases", destination: URL(string: "https://github.com/BireshwarChakravarty/DisplayTuner")!)
                Text("No analytics. No account. No subscription. DDC and Night Shift depend on monitor support and macOS private APIs. Brightness percentages aren't cd/m²; only a colorimeter measures that.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(10).frame(width: 520, height: 660)
            .onAppear { loginEnabled = SMAppService.mainApp.status == .enabled }
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}
