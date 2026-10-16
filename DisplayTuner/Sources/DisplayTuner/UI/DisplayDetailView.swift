import AppKit
import SwiftUI
import TunerCore

/// One display, laid out like a System Settings pane: what you're doing,
/// what will change, what to do by hand, then fine-tuning and details.
/// Apply stays in a bar at the bottom.
struct DisplayDetailView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts
    @ViewState private var savingPreset = false
    @ViewState private var presetName = ""

    private var rec: Recommendation { model.recommendation(for: display) }
    private var changes: [PlannedChange] { model.changes(for: display) }
    private var selectedCount: Int { changes.filter { model.isOn($0, for: display) }.count }
    private var editable: Bool { !model.isBusy && model.confirmation == nil }

    var body: some View {
        Form {
            header
            if let insight { insightSection(insight) }
            activity
            changeList
            if !model.results.isEmpty { lastChange }
            manualSteps
            adjust
            about
            if !rec.notes.isEmpty {
                Section("Good to know") {
                    ForEach(rec.notes, id: \.self) { note in
                        Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(display.name)
        .safeAreaInset(edge: .bottom, spacing: 0) { applyBar }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Identify Display") { model.identify(display) }.disabled(model.isDemo)
                    Button("Open Displays Settings…") { openDisplaySettings() }
                    Divider()
                    Button("Save as Preset…") { savingPreset = true }.disabled(!editable || model.isDemo)
                    Button("Restore Settings From Before Display Tuner") { Task { await model.restoreOriginals() } }
                        .disabled(model.originalSnapshot == nil || !model.canChange)
                    Divider()
                    Button("Export Diagnostics…") { model.exportDiagnostics() }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .alert("Save Preset", isPresented: $savingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { model.savePreset(name: presetName, display: display); presetName = "" }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saves the activity, room lighting, display mode and brightness/contrast. Loading a preset lets you review it before applying.") }
    }

    // MARK: Header

    private var header: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : display.mirrorOf != nil ? "rectangle.on.rectangle" : "display")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(.tint).frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name).font(.title2.weight(.semibold))
                    Text(specLine).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if rec.profile != nil {
                            Label("Researched model", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        if display.hasCalibration {
                            Label("Calibration protected", systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                        if let auto = model.autoState {
                            Label("Auto: \(auto.useCase.title) for \(auto.appName)", systemImage: "wand.and.stars").foregroundStyle(.orange)
                        }
                    }.font(.caption)
                }
                Spacer()
            }.padding(.vertical, 4)
        }
    }

    private var specLine: String {
        var parts: [String] = []
        if let specs = rec.profile?.specs { parts.append("\(specs.size) \(specs.panel.rawValue)") }
        if let master = display.mirrorOf {
            parts.append("Mirroring \(model.displays.first { $0.id == master }?.name ?? "another screen")")
        } else if let mode = display.currentMode {
            parts.append(mode.label)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Insight

    /// The fastest mode at the current desktop size, when the display is running slower.
    private var fasterMode: DisplayMode? {
        guard display.mirrorOf == nil, let current = display.currentMode,
              let best = ModePicker.bestMode(for: current.layout, in: display.modes, policy: .highest),
              best.refreshRate > current.refreshRate + 1 else { return nil }
        return best
    }

    private struct Insight { var text: String; var mode: DisplayMode }

    private var insight: Insight? {
        guard let faster = fasterMode, let current = display.currentMode else { return nil }
        return Insight(text: "Running at \(current.refreshLabel). This display can do \(faster.refreshLabel) at the same size, for smoother motion and lower input lag.",
                       mode: faster)
    }

    private func insightSection(_ insight: Insight) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill").foregroundStyle(.orange)
                Text(insight.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Use \(insight.mode.refreshLabel)") { model.chooseMode(insight.mode, for: display) }
                    .disabled(!model.canChange)
            }
        }
    }

    // MARK: Activity

    private var activity: some View {
        Section {
            Picker("Activity", selection: Binding(get: { model.useCase(for: display.id) },
                                                  set: { model.setUseCase($0, for: display.id) })) {
                ForEach(UseCase.allCases) { Text(shortTitle($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!editable)
            Picker("Room lighting", selection: $model.lighting) {
                ForEach(RoomLighting.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!editable)
        } header: {
            Text("What are you doing?")
        } footer: {
            Text(model.useCase(for: display.id).subtitle + ". Room lighting sets the brightness target.")
        }
    }

    private func shortTitle(_ useCase: UseCase) -> String {
        switch useCase {
        case .competitiveGaming: return "Competitive"
        case .immersiveGaming: return "Immersive"
        case .photoEditing: return "Photo"
        case .videoEditing: return "Video"
        case .everyday: return "Everyday"
        }
    }

    // MARK: Changes

    private var changeList: some View {
        Section {
            if changes.isEmpty {
                Label("Already set for \(model.useCase(for: display.id).title.lowercased()).", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(changes) { change in
                Toggle(isOn: Binding(get: { model.isOn(change, for: display) }, set: { model.setOn($0, change, for: display) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(change.title)
                            if change.isExperimental { Tag(text: "Experimental", color: .orange) }
                            if change.isGlobal { Tag(text: "All screens", color: .secondary) }
                        }
                        Text(change.detail).font(.callout.monospacedDigit()).foregroundStyle(.tint)
                        Text(change.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(!editable)
            }
            ForEach(rec.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Changes")
        } footer: {
            Text("Your current settings are saved first, so Undo always works. A resolution or refresh change reverts after 15 seconds unless you keep it.")
        }
    }

    private var lastChange: some View {
        Section("Last change") {
            ForEach(model.results) { result in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.display.isEmpty ? result.title : "\(result.title) · \(result.display)")
                        Text(result.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.ok ? .green : .orange)
                }
            }
        }
    }

    // MARK: Steps for the person

    private static let places: [(ManualStep.Place, String)] = [
        (.monitorMenu, "On the monitor"), (.systemSettings, "In System Settings"), (.hardware, "Cable"), (.apps, "In your apps")
    ]

    @ViewBuilder private var manualSteps: some View {
        ForEach(Self.places, id: \.0) { entry in
            let (place, title) = entry
            let steps = rec.manualSteps.filter { $0.place == place }
            if !steps.isEmpty {
                Section {
                    ForEach(steps) { step in StepRow(step: step) }
                    if place == .systemSettings {
                        Button("Open Displays Settings…") { openDisplaySettings() }
                    }
                } header: {
                    Text(title)
                } footer: {
                    if place == .monitorMenu { Text("Only the monitor's own buttons can change these. Menu names can differ slightly between units.") }
                }
            }
        }
    }

    // MARK: Fine-tuning

    private var adjust: some View {
        Section {
            if !rec.modeOptions.isEmpty {
                Picker("Resolution & refresh rate", selection: Binding(get: { model.pickerMode(for: display) },
                                                                       set: { if let mode = $0 { model.chooseMode(mode, for: display) } })) {
                    ForEach(rec.modeOptions) { Text($0.label).tag(Optional($0)) }
                }
            }
            if display.hasCalibration {
                Label("Brightness and contrast are locked to protect your calibration.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else if display.mirrorOf == nil && !display.isBuiltIn {
                slider(VCP.brightness, "Brightness")
                slider(VCP.contrast, "Contrast")
            }
        } header: {
            Text("Adjust")
        } footer: {
            Text("Adjustments are staged and appear under Changes until you apply them.")
        }
        .disabled(!editable)
    }

    private func slider(_ vcp: UInt8, _ title: String) -> some View {
        let available = display.ddc.values[vcp] != nil
        let value = (vcp == VCP.brightness ? model.manualBrightness[display.id] : model.manualContrast[display.id])
            ?? Double(display.ddc.values[vcp]?.percent ?? 0)
        return LabeledContent {
            HStack {
                Slider(value: Binding(get: { value }, set: { new in
                    if vcp == VCP.brightness { model.manualBrightness[display.id] = new.rounded() }
                    else { model.manualContrast[display.id] = new.rounded() }
                }), in: 0...100)
                .frame(maxWidth: 260)
                Text(available ? "\(Int(value))%" : "—").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        } label: {
            Text(title)
            if !available { Text("Not available over DDC/CI") }
        }
        .disabled(!available)
    }

    // MARK: About

    private var about: some View {
        Section("About this display") {
            if let specs = rec.profile?.specs {
                LabeledContent("Panel", value: "\(specs.size) \(specs.panel.rawValue), \(specs.native)")
                LabeledContent("Refresh rate", value: specs.maxRefresh)
                LabeledContent("Colour", value: specs.gamut)
                if let hdr = specs.hdr { LabeledContent("HDR", value: hdr) }
                if let vrr = specs.vrr { LabeledContent("Variable refresh", value: vrr) }
            }
            if let primaries = display.primaries {
                LabeledContent("Gamut (from profile)",
                               value: "\(Int((primaries.coverage(of: .sRGB) * 100).rounded()))% sRGB · \(Int((primaries.coverage(of: .displayP3) * 100).rounded()))% Display P3")
            }
            LabeledContent("Colour profile", value: display.customProfilePath == nil
                           ? "\(display.profileName ?? "Display's own")"
                           : (display.profileName ?? display.customProfilePath ?? "Custom"))
            LabeledContent("DDC/CI", value: ddcText)
            if let caps = display.capabilities {
                LabeledContent("Monitor reports") {
                    Text(caps.describedControls.joined(separator: ", ")).multilineTextAlignment(.trailing)
                }
            }
            if let profile = rec.profile {
                DisclosureGroup("Research and sources") {
                    Text(profile.confidence).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(sources) { source in
                        if let url = URL(string: source.url) { Link(source.title, destination: url).font(.callout) }
                    }
                }
            }
        }
    }

    private var ddcText: String {
        switch display.ddc {
        case .unknown, .probing: return "Checking…"
        case .unavailable: return display.isBuiltIn ? "Not needed" : "Not available: use the monitor's buttons"
        case .available(let values):
            let parts = [VCP.brightness, VCP.contrast].compactMap { vcp in values[vcp].map { "\(VCP.name(vcp).lowercased()) \($0.percent)%" } }
            return parts.isEmpty ? "Connected" : "Connected · " + parts.joined(separator: ", ")
        }
    }

    private var sources: [Source] {
        var seen = Set<String>()
        return ((rec.profile?.sources ?? []) + rec.sources).filter { seen.insert($0.url).inserted }
    }

    // MARK: Apply bar

    private var statusText: String {
        if model.isDemo { return "Demo: simulated displays, nothing is changed" }
        if model.recoveryRequired { return "An interrupted change needs to be restored" }
        if model.isBusy { return "Applying…" }
        switch selectedCount {
        case 0: return "Nothing to change"
        case 1: return "1 change selected"
        default: return "\(selectedCount) changes selected"
        }
    }

    private var applyBar: some View {
        HStack(spacing: 12) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Text(statusText).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Undo Last Apply") { Task { await model.undoLastApply() } }
                .disabled(model.lastSnapshot == nil || !model.canChange)
            Button(model.recoveryRequired ? "Retry Recovery" : "Apply") {
                Task {
                    if model.recoveryRequired { await model.undoLastApply() }
                    else { await model.apply(to: [display.id]) }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.recoveryRequired ? model.isBusy : (!model.canChange || selectedCount == 0))
        }
        .controlSize(.large)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct StepRow: View {
    let step: ManualStep

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(step.sources) { source in
                    if let url = URL(string: source.url) { Link(source.title, destination: url).font(.caption) }
                }
            }
            .padding(.vertical, 4)
        } label: {
            LabeledContent {
                Text(step.value).foregroundStyle(.primary).multilineTextAlignment(.trailing)
            } label: {
                Text(step.setting)
                Text(step.path)
            }
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
