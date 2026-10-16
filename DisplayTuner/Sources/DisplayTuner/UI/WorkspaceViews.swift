import AppKit
import SwiftUI
import ServiceManagement
import TunerCore

struct SavedPresetsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Made for your workflow", title: "Your perfect setups.", subtitle: "Save a display setup once. Come back to it whenever you need it.")
                if model.savedPresets.isEmpty {
                    ContentUnavailableView("Keep a good thing", systemImage: "square.stack.3d.up", description: Text("Choose an activity in Display Studio, fine-tune your controls, then choose Save preset."))
                        .frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                    ForEach(model.savedPresets) { preset in
                        StudioCard {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack { Image(systemName: preset.useCase.symbol).font(.title).foregroundStyle(Color.studioCyan); Spacer(); Menu {
                                    Button("Delete preset", role: .destructive) { model.deletePreset(preset.id) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25) }
                                Text(preset.name).font(.title3.bold())
                                Text(preset.displayName).font(.caption).foregroundStyle(.secondary)
                                Text(preset.useCase.title + " · " + preset.lighting.title + " room").font(.caption).foregroundStyle(.secondary)
                                if let mode = preset.mode { Text(mode.label).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.studioCyan) }
                                Button { model.loadPreset(preset) } label: { Label("Load & review", systemImage: "arrow.up.right") }.buttonStyle(StudioButton()).disabled(model.isBusy || model.confirmation != nil)
                            }
                        }
                    }
                }
            }.padding(30)
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    PageHeading(eyebrow: "A clear trail", title: "Every adjustment, recorded.", subtitle: "Your last 100 operations, stored only on this Mac.")
                    Spacer()
                    Button { model.exportDiagnostics() } label: { Label("Export diagnostics", systemImage: "square.and.arrow.up") }.buttonStyle(StudioButton())
                }
                if model.activity.isEmpty {
                    ContentUnavailableView("A fresh start", systemImage: "clock", description: Text("Apply a change and its result will appear here."))
                        .frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                ForEach(model.activity) { entry in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: entry.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(entry.ok ? Color.studioCyan : .orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title).font(.system(size: 13, weight: .semibold))
                            Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.tertiary)
                    }.padding(18).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(30)
        }
    }
}

struct PageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-0.7)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct StudioSettingsView: View {
    @AppStorage("appearance") private var appearance = "dark"
    @ViewState private var loginEnabled = SMAppService.mainApp.status == .enabled
    @ViewState private var error: String?
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) { Text("System").tag("system"); Text("Dark studio").tag("dark"); Text("Light studio").tag("light") }
                Text("Liquid Glass is available on macOS 26 and later. Earlier versions use native translucent materials. Reduce Transparency is respected.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open Display Tuner at login", isOn: Binding(get: { loginEnabled }, set: { value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginEnabled = SMAppService.mainApp.status == .enabled
                        if SMAppService.mainApp.status == .requiresApproval { error = "Approve Display Tuner in System Settings → General → Login Items." }
                    } catch { self.error = error.localizedDescription }
                }))
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("About Display Tuner") {
                HStack(spacing: 14) { AppMark().frame(width: 50, height: 50); VStack(alignment: .leading, spacing: 4) { Text("Display Tuner 2.0.0").font(.headline); Text("A better view, every day.").foregroundStyle(.secondary) } }
                Link("Source, updates & releases", destination: URL(string: "https://github.com/BireshwarChakravarty/DisplayTuner")!)
                Text("No analytics. No account. No subscription. DDC and Night Shift depend on monitor support and macOS private APIs. Brightness estimates are not colorimeter measurements.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(10).frame(width: 500, height: 490)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
}
