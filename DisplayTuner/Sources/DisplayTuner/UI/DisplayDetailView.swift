import AppKit
import SwiftUI
import TunerCore

/// One display: an overview with its colour gamut, activity tiles that preview
/// what they set, the changes as before → after, a checklist for what only
/// the monitor can change, then fine-tuning and details. Apply floats below.
struct DisplayDetailView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts
    @ViewState private var savingPreset = false
    @ViewState private var presetName = ""
    @ViewState private var expandedSteps: Set<String> = []
    @AppStorage("doneSteps") private var doneStepsRaw = ""

    private var rec: Recommendation { model.recommendation(for: display) }
    private var changes: [PlannedChange] { model.changes(for: display) }
    private var selectedCount: Int { changes.filter { model.isOn($0, for: display) }.count }
    private var editable: Bool { !model.isBusy && model.confirmation == nil }
    private var useCase: UseCase { model.useCase(for: display.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overview
                if let faster = fasterMode, let current = display.currentMode { refreshBanner(current: current, faster: faster) }
                activityTiles
                changeList
                if !model.results.isEmpty { lastChange }
                checklist
                adjust
                about
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 100)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
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

    // MARK: Overview

    private var overview: some View {
        Card {
            HStack(alignment: .top, spacing: 24) {
                GamutDiagram(primaries: display.primaries).frame(width: 210)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.name).font(.title2.weight(.semibold))
                        Text(specLine).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            if rec.profile != nil { Badge(text: "Researched model", symbol: "checkmark.seal.fill", color: .green) }
                            if display.hasCalibration { Badge(text: "Calibration protected", symbol: "lock.fill", color: .secondary) }
                            if let auto = model.autoState { Badge(text: "Auto · \(auto.appName)", symbol: "wand.and.stars", color: .orange) }
                        }
                    }
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Stat(title: "Refresh", value: display.currentMode?.refreshLabel ?? "—", symbol: "speedometer",
                                 detail: fasterMode.map { "\($0.refreshLabel) available" } ?? "Fastest at this size",
                                 progress: refreshProgress, warn: fasterMode != nil)
                            Stat(title: "Looks like", value: display.currentMode.map { "\($0.width) × \($0.height)" } ?? "—", symbol: "rectangle.dashed",
                                 detail: display.nativePixels.map { "Panel \($0.width) × \($0.height)" } ?? "", progress: nil)
                        }
                        GridRow {
                            Stat(title: "Colour", value: colourMode, symbol: "paintpalette",
                                 detail: display.primaries.map { "\(percent($0.coverage(of: .sRGB))) sRGB · \(percent($0.coverage(of: .displayP3))) P3" } ?? "Gamut unknown",
                                 progress: display.primaries.map { $0.coverage(of: .displayP3) })
                            Stat(title: "Brightness", value: brightnessValue, symbol: "sun.max",
                                 detail: brightnessDetail, progress: display.ddc.values[VCP.brightness].map { Double($0.percent) / 100 })
                        }
                    }
                }
            }
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

    private var refreshProgress: Double? {
        guard let current = display.currentMode?.refreshRate, display.maxRefresh > 0 else { return nil }
        let best = display.currentMode.flatMap { ModePicker.bestMode(for: $0.layout, in: display.modes, policy: .highest)?.refreshRate } ?? display.maxRefresh
        return best > 0 ? min(1, current / best) : nil
    }

    private var colourMode: String {
        if let path = display.customProfilePath, path.hasSuffix(ProfileChoice.sRGBFile) { return "sRGB" }
        if display.hasCalibration { return "Calibrated" }
        return (display.primaries?.isWideGamut ?? false) ? "Wide gamut" : "Standard"
    }

    private var brightnessValue: String {
        guard let level = display.ddc.values[VCP.brightness] else { return display.ddc.isAvailable ? "—" : "Manual" }
        if let peak = rec.profile?.specs.peakSDRNits { return "≈\(Int((Double(level.percent) / 100 * peak).rounded())) nits" }
        return "\(level.percent)%"
    }

    private var brightnessDetail: String {
        guard let level = display.ddc.values[VCP.brightness] else { return "Use the monitor's buttons" }
        return "\(level.percent)% over DDC/CI"
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    // MARK: Refresh banner

    /// The fastest mode at the current desktop size, when the display is running slower.
    private var fasterMode: DisplayMode? {
        guard display.mirrorOf == nil, let current = display.currentMode,
              let best = ModePicker.bestMode(for: current.layout, in: display.modes, policy: .highest),
              best.refreshRate > current.refreshRate + 1 else { return nil }
        return best
    }

    private func refreshBanner(current: DisplayMode, faster: DisplayMode) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Running at \(current.refreshLabel), \(faster.refreshLabel) is available").font(.headline)
                Text("Same resolution, smoother motion and lower input lag.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Use \(faster.refreshLabel)") { model.chooseMode(faster, for: display) }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(!model.canChange)
        }
        .padding(16)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.3)))
    }

    // MARK: Activity

    private var activityTiles: some View {
        Card(title: "What are you doing?", trailing: {
            Picker("Room", selection: $model.lighting) {
                Label("Dim", systemImage: "moon").tag(RoomLighting.dim)
                Label("Normal", systemImage: "lamp.desk").tag(RoomLighting.normal)
                Label("Bright", systemImage: "sun.max").tag(RoomLighting.bright)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .disabled(!editable)
            .help("Room lighting sets the brightness target")
        }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(UseCase.allCases) { option in
                    ActivityTile(useCase: option, selected: option == useCase, summary: summary(for: option)) {
                        model.setUseCase(option, for: display.id)
                    }
                    .disabled(!editable)
                }
            }
        }
    }

    /// What a preset will set, in a few words: "160 Hz · sRGB · 120 nits".
    private func summary(for option: UseCase) -> String {
        var parts: [String] = []
        if display.mirrorOf == nil, let current = display.currentMode,
           let mode = ModePicker.bestMode(for: current.layout, in: display.modes,
                                          policy: option == .videoEditing ? .videoFriendly : .highest) {
            parts.append(mode.refreshLabel)
        }
        if !display.hasCalibration {
            parts.append(option.isEditing && rec.profile?.specs.hasSRGBMode == true ? "sRGB" : "Native colour")
            if display.ddc.values[VCP.brightness] != nil {
                let nits = option.isEditing ? model.lighting.editingNits(for: option) : model.lighting.comfortNits
                parts.append("\(Int(nits)) nits")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Changes

    private var changeList: some View {
        Card(title: "Changes", trailing: {
            Text(selectedCount == 0 ? "Nothing to change" : "\(selectedCount) selected")
                .font(.callout).foregroundStyle(.secondary)
        }) {
            VStack(spacing: 0) {
                if changes.isEmpty {
                    Label("Already set for \(useCase.title.lowercased()).", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                    if index > 0 { Divider().padding(.leading, 44) }
                    ChangeRow(change: change, isOn: Binding(get: { model.isOn(change, for: display) },
                                                            set: { model.setOn($0, change, for: display) }))
                        .disabled(!editable)
                }
                ForEach(rec.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
        }
    }

    private var lastChange: some View {
        Card(title: "Last change") {
            VStack(alignment: .leading, spacing: 8) {
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
    }

    // MARK: Checklist

    private struct Place {
        let place: ManualStep.Place
        let title: String
        let symbol: String
    }

    private static let places: [Place] = [
        Place(place: .monitorMenu, title: "On the monitor", symbol: "slider.horizontal.3"),
        Place(place: .systemSettings, title: "In System Settings", symbol: "gearshape"),
        Place(place: .hardware, title: "Cable", symbol: "cable.connector"),
        Place(place: .apps, title: "In your apps", symbol: "square.grid.2x2")
    ]

    private var doneSteps: Set<String> { Set(doneStepsRaw.split(separator: "\n").map(String.init)) }

    private func stepKey(_ step: ManualStep) -> String { "\(display.key)|\(useCase.rawValue)|\(step.id)" }

    private func toggleDone(_ step: ManualStep) {
        var done = doneSteps
        let key = stepKey(step)
        if done.contains(key) { done.remove(key) } else { done.insert(key) }
        doneStepsRaw = done.sorted().joined(separator: "\n")
    }

    private func toggleExpanded(_ step: ManualStep) {
        if expandedSteps.contains(step.id) { expandedSteps.remove(step.id) } else { expandedSteps.insert(step.id) }
    }

    @ViewBuilder private var checklist: some View {
        let steps = rec.manualSteps
        if !steps.isEmpty {
            let done = doneSteps
            let doneCount = steps.filter { done.contains(stepKey($0)) }.count
            Card(title: "Finish by hand", trailing: {
                HStack(spacing: 8) {
                    ProgressView(value: Double(doneCount), total: Double(steps.count)).frame(width: 80)
                    Text("\(doneCount) of \(steps.count) done").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Only the monitor's buttons, System Settings or your apps can change these. Tick them off as you go.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(Self.places, id: \.title) { place in
                        let group = steps.filter { $0.place == place.place }
                        if !group.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(place.title, systemImage: place.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    if place.place == .systemSettings {
                                        Button("Open Displays Settings…") { openDisplaySettings() }.controlSize(.small)
                                    }
                                }
                                ForEach(group) { step in
                                    StepRow(step: step, done: done.contains(stepKey(step)), expanded: expandedSteps.contains(step.id),
                                            toggleDone: { toggleDone(step) }, toggleExpanded: { toggleExpanded(step) })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Fine-tuning

    private var adjust: some View {
        Card(title: "Adjust") {
            VStack(alignment: .leading, spacing: 12) {
                if !rec.modeOptions.isEmpty {
                    LabeledContent("Resolution & refresh rate") {
                        Picker("Resolution & refresh rate", selection: Binding(get: { model.pickerMode(for: display) },
                                                                               set: { if let mode = $0 { model.chooseMode(mode, for: display) } })) {
                            ForEach(rec.modeOptions) { mode in Text(mode.label).tag(Optional(mode)) }
                        }
                        .labelsHidden().frame(maxWidth: 320)
                    }
                }
                if display.hasCalibration {
                    Label("Brightness and contrast are locked to protect your calibration.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } else if display.mirrorOf == nil && !display.isBuiltIn {
                    slider(VCP.brightness, "Brightness", "sun.min", "sun.max")
                    slider(VCP.contrast, "Contrast", "circle.lefthalf.filled", "circle.righthalf.filled")
                }
                Text("Adjustments are staged and appear under Changes until you apply them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!editable)
        }
    }

    private func slider(_ vcp: UInt8, _ title: String, _ low: String, _ high: String) -> some View {
        let available = display.ddc.values[vcp] != nil
        let value = (vcp == VCP.brightness ? model.manualBrightness[display.id] : model.manualContrast[display.id])
            ?? Double(display.ddc.values[vcp]?.percent ?? 0)
        return LabeledContent(title) {
            HStack(spacing: 8) {
                Image(systemName: low).foregroundStyle(.secondary)
                Slider(value: Binding(get: { value }, set: { new in
                    if vcp == VCP.brightness { model.manualBrightness[display.id] = new.rounded() }
                    else { model.manualContrast[display.id] = new.rounded() }
                }), in: 0...100)
                Image(systemName: high).foregroundStyle(.secondary)
                Text(available ? "\(Int(value))%" : "—").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
            .frame(maxWidth: 360)
        }
        .disabled(!available)
        .help(available ? "" : "Not available over DDC/CI: use the monitor's buttons")
    }

    // MARK: About

    private var about: some View {
        Card(title: "About this display") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let specs = rec.profile?.specs {
                        row("Panel", "\(specs.size) \(specs.panel.rawValue), \(specs.native)")
                        row("Refresh rate", specs.maxRefresh)
                        row("Colour", specs.gamut)
                        if let hdr = specs.hdr { row("HDR", hdr) }
                        if let vrr = specs.vrr { row("Variable refresh", vrr) }
                    }
                    row("Colour profile", display.customProfilePath == nil
                        ? "\(display.profileName ?? "Display's own")"
                        : (display.profileName ?? display.customProfilePath ?? "Custom"))
                    row("DDC/CI", ddcText)
                    if let caps = display.capabilities { row("Monitor reports", caps.describedControls.joined(separator: ", ")) }
                }
                if !rec.notes.isEmpty {
                    Divider()
                    ForEach(rec.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let profile = rec.profile {
                    DisclosureGroup("Research and sources") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.confidence).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            ForEach(sources) { source in
                                if let url = URL(string: source.url) { Link(source.title, destination: url).font(.callout) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
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
        case 1: return "1 change ready · your current settings are saved first"
        default: return "\(selectedCount) changes ready · your current settings are saved first"
        }
    }

    private var applyBar: some View {
        HStack(spacing: 12) {
            Image(systemName: useCase.symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(useCase.title).font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button("Undo") { Task { await model.undoLastApply() } }
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
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 24).padding(.bottom, 14)
    }

    private func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Components

/// A rounded panel with an optional title and trailing accessory.
struct Card<Trailing: View, Content: View>: View {
    var title: String?
    var trailing: () -> Trailing
    var content: () -> Content

    init(title: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    trailing()
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

extension Card where Trailing == EmptyView {
    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

struct Badge: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let symbol: String
    let detail: String
    let progress: Double?
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(warn ? Color.orange : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let progress {
                ProgressView(value: max(0, min(1, progress))).tint(warn ? Color.orange : Color.accentColor)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ActivityTile: View {
    let useCase: UseCase
    let selected: Bool
    let summary: String
    let action: () -> Void
    @ViewState private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: useCase.symbol).font(.title2)
                        .foregroundStyle(selected ? Color.white : Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(selected ? Color.accentColor : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                }
                Text(useCase.title).font(.headline)
                Text(useCase.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                if !summary.isEmpty {
                    Text(summary).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.tint).lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(selected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(hovered ? 0.06 : 0.03),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(useCase.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ChangeRow: View {
    let change: PlannedChange
    @Binding var isOn: Bool

    private var symbol: String {
        switch change.change {
        case .mode: return "display"
        case .colorProfile: return "paintpalette"
        case .ddc(let target):
            if target.vcp == VCP.brightness { return "sun.max" }
            if target.vcp == VCP.contrast { return "circle.lefthalf.filled" }
            return "slider.horizontal.3"
        case .nightShift: return "moon.stars"
        }
    }

    /// "60 Hz → 160 Hz" split into before and after.
    private var before: String {
        let pieces = change.detail.components(separatedBy: " → ")
        return pieces.count == 2 ? pieces[0] : ""
    }

    private var after: String {
        let pieces = change.detail.components(separatedBy: " → ")
        return pieces.count == 2 ? pieces[1] : change.detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.medium)).foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(change.title).font(.headline)
                    if change.isExperimental { Badge(text: "Experimental", symbol: "flask", color: .orange) }
                    if change.isGlobal { Badge(text: "All screens", symbol: "rectangle.on.rectangle", color: .secondary) }
                }
                HStack(spacing: 6) {
                    if !before.isEmpty {
                        Text(before).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(after).fontWeight(.semibold).foregroundStyle(.tint)
                }
                .font(.callout.monospacedDigit())
                Text(change.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(change.title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 10)
    }
}

private struct StepRow: View {
    let step: ManualStep
    let done: Bool
    let expanded: Bool
    let toggleDone: () -> Void
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button(action: toggleDone) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3)
                        .foregroundStyle(done ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "Mark \(step.setting) as not done" : "Mark \(step.setting) as done")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(step.setting).font(.body.weight(.medium)).strikethrough(done)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(step.value).fontWeight(.semibold).foregroundStyle(done ? Color.secondary : Color.accentColor)
                    }
                    Text(step.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: toggleExpanded) {
                    Image(systemName: expanded ? "chevron.up.circle" : "info.circle")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Why")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(step.sources) { source in
                        if let url = URL(string: source.url) { Link(source.title, destination: url).font(.caption) }
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(done ? 0.02 : 0.04), in: RoundedRectangle(cornerRadius: 10))
        .opacity(done ? 0.75 : 1)
    }
}
