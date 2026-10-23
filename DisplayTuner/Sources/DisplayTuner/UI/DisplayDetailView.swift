import AppKit
import SwiftUI
import TunerCore

/// One display, laid out the way Apple's own Liquid Glass apps are: an
/// edge-to-edge hero that extends under the sidebar, presets as a strip of
/// cards, grouped sections for what will change and what's left to do, a
/// research inspector on the trailing edge, and Apply floating in glass.
struct DisplayDetailView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts
    @ViewState private var savingPreset = false
    @ViewState private var presetName = ""
    @ViewState private var expandedSteps: Set<String> = []
    @AppStorage("doneSteps") private var doneStepsRaw = ""
    @AppStorage("showInspector") private var showInspector = false

    private var rec: Recommendation { model.recommendation(for: display) }
    private var changes: [PlannedChange] { model.changes(for: display) }
    private var selectedCount: Int { changes.filter { model.isOn($0, for: display) }.count }
    private var editable: Bool { !model.isBusy && model.confirmation == nil }
    private var useCase: UseCase { model.useCase(for: display.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 30) {
                    presets
                    changeSection
                    if !model.results.isEmpty { lastChange }
                    checklist
                    adjust
                }
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 36)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(display.name)
        .safeAreaBar(edge: .bottom) { applyBar }
        .inspector(isPresented: $showInspector) {
            DisplayInspector(display: display, rec: rec)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Identify Display", systemImage: "eye") { model.identify(display) }.disabled(model.isDemo)
                    Button("Open Displays Settings…", systemImage: "gearshape") { openDisplaySettings() }
                    Divider()
                    Button("Save as Preset…", systemImage: "square.and.arrow.down") { savingPreset = true }
                        .disabled(!editable || model.isDemo)
                    Button("Restore Settings From Before Display Tuner", systemImage: "clock.arrow.circlepath") {
                        Task { await model.restoreOriginals() }
                    }
                    .disabled(model.originalSnapshot == nil || !model.canChange)
                    Divider()
                    Button("Export Diagnostics…", systemImage: "doc.text.magnifyingglass") { model.exportDiagnostics() }
                } label: { Label("More", systemImage: "ellipsis") }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Display Details", systemImage: "info") }
                    .help("Show research, specifications and sources")
            }
        }
        .alert("Save Preset", isPresented: $savingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { model.savePreset(name: presetName, display: display); presetName = "" }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saves the activity, room lighting, display mode and brightness/contrast. Loading a preset lets you review it before applying.") }
    }

    // MARK: Hero

    private var hero: some View {
        HeroArtwork(useCase: useCase)
            .frame(height: 300)
            .backgroundExtensionEffect()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 20) {
                        MonitorGlyph(display: display, useCase: useCase)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(display.name)
                                .font(.system(size: 30, weight: .bold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(specLine).font(.title3).opacity(0.85)
                            HStack(spacing: 8) {
                                if rec.profile != nil { HeroTag(text: "Researched model", symbol: "checkmark.seal.fill") }
                                if display.hasCalibration { HeroTag(text: "Calibration protected", symbol: "lock.fill") }
                                if let auto = model.autoState { HeroTag(text: "Auto · \(auto.appName)", symbol: "wand.and.stars") }
                            }
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    }
                    stats
                }
                .padding(.horizontal, 28).padding(.bottom, 22)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
    }

    private var stats: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                StatChip(title: "Refresh", value: display.currentMode?.refreshLabel ?? "—", symbol: "speedometer",
                         detail: fasterMode.map { "\($0.refreshLabel) available" } ?? "Fastest at this size",
                         warn: fasterMode != nil)
                StatChip(title: "Looks like", value: display.currentMode.map { "\($0.width) × \($0.height)" } ?? "—",
                         symbol: "rectangle.dashed",
                         detail: display.nativePixels.map { "Panel \($0.width) × \($0.height)" } ?? "")
                StatChip(title: "Colour", value: colourMode, symbol: "paintpalette",
                         detail: display.primaries.map { "\(percent($0.coverage(of: .sRGB))) sRGB · \(percent($0.coverage(of: .displayP3))) P3" } ?? "Gamut unknown")
                StatChip(title: "Brightness", value: brightnessValue, symbol: "sun.max", detail: brightnessDetail)
                if let faster = fasterMode {
                    Button { model.chooseMode(faster, for: display) } label: {
                        Label("Use \(faster.refreshLabel)", systemImage: "bolt.fill")
                            .font(.headline)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .disabled(!model.canChange)
                    .help("Same resolution at \(faster.refreshLabel): smoother motion and lower input lag. Review it under Changes, then Apply.")
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

    /// The fastest mode at the current desktop size, when the display is running slower.
    private var fasterMode: DisplayMode? {
        guard display.mirrorOf == nil, let current = display.currentMode,
              let best = ModePicker.bestMode(for: current.layout, in: display.modes, policy: .highest),
              best.refreshRate > current.refreshRate + 1 else { return nil }
        return best
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("What are you doing?")
                Spacer()
                Picker("Room", selection: $model.lighting) {
                    Label("Dim", systemImage: "moon").tag(RoomLighting.dim)
                    Label("Normal", systemImage: "lamp.desk").tag(RoomLighting.normal)
                    Label("Bright", systemImage: "sun.max").tag(RoomLighting.bright)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .disabled(!editable)
                .help("How bright the room is. It sets the brightness target.")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(UseCase.allCases) { option in
                        PresetCard(useCase: option, selected: option == useCase, summary: summary(for: option)) {
                            withAnimation(.smooth) { model.setUseCase(option, for: display.id) }
                        }
                        .disabled(!editable)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
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
            let wide = display.primaries?.isWideGamut ?? rec.profile?.specs.isWideGamut ?? false
            if option.isEditing && rec.profile?.specs.hasSRGBMode == true { parts.append("sRGB") }
            else if option == .macbookLook && wide { parts.append("P3 colour") }
            else { parts.append("Native colour") }
            if display.ddc.values[VCP.brightness] != nil {
                let nits = model.lighting.targetNits(for: option)
                let peak = rec.profile?.specs.peakSDRNits
                parts.append(peak.map { nits >= $0 } ?? false ? "Max brightness" : "\(Int(nits)) nits")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Changes

    private var changeSection: some View {
        GroupedSection(title: "Changes", trailing: {
            Text(selectedCount == 0 ? "Nothing to change" : "\(selectedCount) selected")
                .foregroundStyle(.secondary)
        }, footer: rec.warnings.isEmpty ? nil : AnyView(warnings)) {
            if changes.isEmpty {
                Label("Already set for \(useCase.title.lowercased()).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                if index > 0 { Divider().padding(.leading, 60) }
                ChangeRow(change: change, isOn: Binding(get: { model.isOn(change, for: display) },
                                                        set: { model.setOn($0, change, for: display) }))
                    .disabled(!editable)
            }
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rec.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lastChange: some View {
        GroupedSection(title: "Last change") {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                if index > 0 { Divider().padding(.leading, 46) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.ok ? .green : .orange)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.display.isEmpty ? result.title : "\(result.title) · \(result.display)")
                        Text(result.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
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
        Place(place: .monitorMenu, title: "On the Monitor", symbol: "slider.horizontal.3"),
        Place(place: .systemSettings, title: "In System Settings", symbol: "gearshape"),
        Place(place: .hardware, title: "Cable", symbol: "cable.connector"),
        Place(place: .apps, title: "In Your Apps", symbol: "square.grid.2x2")
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("Finish by Hand")
                    Spacer()
                    Gauge(value: Double(doneCount), in: 0...Double(steps.count)) { EmptyView() }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .scaleEffect(0.55).frame(width: 30, height: 30)
                    Text("\(doneCount) of \(steps.count) done").foregroundStyle(.secondary).monospacedDigit()
                }
                Text("Only the monitor's buttons, System Settings or your apps can change these. Tick them off as you go.")
                    .foregroundStyle(.secondary)
                ForEach(Self.places, id: \.title) { place in
                    let group = steps.filter { $0.place == place.place }
                    if !group.isEmpty {
                        GroupedSection(title: place.title, symbol: place.symbol, small: true, trailing: {
                            if place.place == .systemSettings {
                                Button("Open Displays Settings…") { openDisplaySettings() }
                                    .buttonStyle(.glass).controlSize(.small)
                            }
                        }) {
                            ForEach(Array(group.enumerated()), id: \.element.id) { index, step in
                                if index > 0 { Divider().padding(.leading, 46) }
                                StepRow(step: step, done: done.contains(stepKey(step)), expanded: expandedSteps.contains(step.id),
                                        toggleDone: { toggleDone(step) }, toggleExpanded: { toggleExpanded(step) })
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Adjust

    private var adjust: some View {
        GroupedSection(title: "Adjust", footer: AnyView(Text("Adjustments are staged and appear under Changes until you apply them.")
            .foregroundStyle(.secondary))) {
            VStack(spacing: 0) {
                if !rec.modeOptions.isEmpty {
                    SettingRow(title: "Resolution & refresh rate", symbol: "display") {
                        Picker("Resolution & refresh rate", selection: Binding(get: { model.pickerMode(for: display) },
                                                                               set: { if let mode = $0 { model.chooseMode(mode, for: display) } })) {
                            ForEach(rec.modeOptions) { mode in Text(mode.label).tag(Optional(mode)) }
                        }
                        .labelsHidden().frame(maxWidth: 320)
                    }
                }
                if display.hasCalibration {
                    if !rec.modeOptions.isEmpty { Divider().padding(.leading, 46) }
                    Label("Brightness and contrast are locked to protect your calibration.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else if display.mirrorOf == nil && !display.isBuiltIn {
                    if !rec.modeOptions.isEmpty { Divider().padding(.leading, 46) }
                    slider(VCP.brightness, "Brightness", "sun.max")
                    Divider().padding(.leading, 46)
                    slider(VCP.contrast, "Contrast", "circle.lefthalf.filled")
                }
            }
            .disabled(!editable)
        }
    }

    private func slider(_ vcp: UInt8, _ title: String, _ symbol: String) -> some View {
        let available = display.ddc.values[vcp] != nil
        let value = (vcp == VCP.brightness ? model.manualBrightness[display.id] : model.manualContrast[display.id])
            ?? Double(display.ddc.values[vcp]?.percent ?? 0)
        return SettingRow(title: title, symbol: symbol) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: { new in
                    if vcp == VCP.brightness { model.manualBrightness[display.id] = new.rounded() }
                    else { model.manualContrast[display.id] = new.rounded() }
                }), in: 0...100)
                Text(available ? "\(Int(value))%" : "—").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            .frame(maxWidth: 320)
        }
        .disabled(!available)
        .help(available ? "" : "Not available over DDC/CI: use the monitor's buttons")
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
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: useCase.symbol).font(.title3).foregroundStyle(.tint).frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(useCase.title).font(.headline)
                        Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if model.isBusy { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 12)
                Button { Task { await model.undoLastApply() } } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.glass)
                .disabled(model.lastSnapshot == nil || !model.canChange)
                Button {
                    Task {
                        if model.recoveryRequired { await model.undoLastApply() }
                        else { await model.apply(to: [display.id]) }
                    }
                } label: {
                    Text(model.recoveryRequired ? "Retry Recovery" : "Apply").frame(minWidth: 70)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.recoveryRequired ? model.isBusy : (!model.canChange || selectedCount == 0))
            }
            .controlSize(.extraLarge)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Hero pieces

/// The hero background: a soft mesh gradient in each preset's own colours.
struct HeroArtwork: View {
    let useCase: UseCase

    var body: some View {
        let c = useCase.palette
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.55, 0.45], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1]
        ], colors: [
            c[0], c[1], c[2],
            c[1], c[2], c[0],
            c[3], c[3], c[1]
        ])
        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom))
        .animation(.smooth(duration: 0.6), value: useCase)
    }
}

extension UseCase {
    /// Four colours that suggest what the preset is for.
    var palette: [Color] {
        switch self {
        case .competitiveGaming: return [Color(red: 0.95, green: 0.25, blue: 0.2), Color(red: 1, green: 0.55, blue: 0.15), Color(red: 0.55, green: 0.1, blue: 0.3), Color(red: 0.2, green: 0.05, blue: 0.15)]
        case .immersiveGaming: return [Color(red: 0.45, green: 0.25, blue: 0.95), Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.85, green: 0.3, blue: 0.75), Color(red: 0.1, green: 0.08, blue: 0.3)]
        case .photoEditing: return [Color(red: 0.55, green: 0.6, blue: 0.62), Color(red: 0.75, green: 0.72, blue: 0.66), Color(red: 0.35, green: 0.42, blue: 0.48), Color(red: 0.15, green: 0.17, blue: 0.2)]
        case .videoEditing: return [Color(red: 0.1, green: 0.35, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.25), Color(red: 0.1, green: 0.2, blue: 0.35), Color(red: 0.05, green: 0.08, blue: 0.15)]
        case .macbookLook: return [Color(red: 0.2, green: 0.45, blue: 1), Color(red: 0.95, green: 0.35, blue: 0.6), Color(red: 0.5, green: 0.3, blue: 0.95), Color(red: 0.1, green: 0.1, blue: 0.35)]
        case .everyday: return [Color(red: 0.2, green: 0.6, blue: 0.95), Color(red: 0.35, green: 0.8, blue: 0.75), Color(red: 0.15, green: 0.4, blue: 0.75), Color(red: 0.05, green: 0.15, blue: 0.3)]
        }
    }
}

/// A small drawing of the monitor, its screen showing the preset's colours.
private struct MonitorGlyph: View {
    let display: DisplayFacts
    let useCase: UseCase

    var body: some View {
        let aspect = display.nativePixels.map { Double($0.width) / Double(max($0.height, 1)) } ?? 16.0 / 9.0
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: Array(useCase.palette.prefix(3)), startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: useCase.symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(5)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .aspectRatio(aspect, contentMode: .fit)
                .frame(width: 150)
            if !display.isBuiltIn {
                Rectangle().fill(.white.opacity(0.55)).frame(width: 18, height: 14)
                Capsule().fill(.white.opacity(0.55)).frame(width: 56, height: 5)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .accessibilityHidden(true)
    }
}

private struct HeroTag: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}

private struct StatChip: View {
    let title: String
    let value: String
    let symbol: String
    let detail: String
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(warn ? Color.orange : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minWidth: 130, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

// MARK: - Sections

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.title2.weight(.bold))
    }
}

/// A grouped, inset section like System Settings: a title above, rows on a
/// rounded background, an optional footer below.
struct GroupedSection<Trailing: View, Content: View>: View {
    var title: String
    var symbol: String?
    var small = false
    var trailing: () -> Trailing
    var footer: AnyView?
    var content: () -> Content

    init(title: String, symbol: String? = nil, small: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing,
         footer: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.small = small
        self.trailing = trailing
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if small {
                    Label(title, systemImage: symbol ?? "circle").font(.headline).foregroundStyle(.secondary)
                } else {
                    SectionTitle(title)
                }
                Spacer()
                trailing()
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
            if let footer { footer.font(.callout).padding(.horizontal, 4) }
        }
    }
}

extension GroupedSection where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, small: Bool = false, footer: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, symbol: symbol, small: small, trailing: { EmptyView() }, footer: footer, content: content)
    }
}

/// A settings row: a coloured symbol tile, a title, and the control.
private struct SettingRow<Control: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: symbol)
            Text(title)
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// The small rounded icon System Settings puts beside each row.
struct SymbolTile: View {
    let symbol: String
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color.gradient, in: .rect(cornerRadius: 6))
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

/// A preset as a card: artwork in the preset's colours, its symbol, title and
/// what it will set.
private struct PresetCard: View {
    let useCase: UseCase
    let selected: Bool
    let summary: String
    let action: () -> Void
    @ViewState private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    HeroArtwork(useCase: useCase)
                        .frame(height: 78)
                        .overlay {
                            Image(systemName: useCase.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                        }
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .glassEffect(.regular.tint(.accentColor), in: .circle)
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(useCase.title).font(.headline).lineLimit(1)
                    Text(useCase.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                    if !summary.isEmpty {
                        Text(summary).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.tint).lineLimit(1)
                    }
                }
                .padding(12)
            }
            .frame(width: 196)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: selected ? 2.5 : 1))
            .shadow(color: .black.opacity(hovered ? 0.18 : 0.08), radius: hovered ? 10 : 4, y: hovered ? 4 : 2)
            .scaleEffect(hovered ? 1.02 : 1)
            .animation(.smooth(duration: 0.2), value: hovered)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(useCase.title)
        .accessibilityHint(summary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ChangeRow: View {
    let change: PlannedChange
    @Binding var isOn: Bool

    private var symbol: (String, Color) {
        switch change.change {
        case .mode: return ("display", .blue)
        case .colorProfile: return ("paintpalette.fill", .purple)
        case .ddc(let target):
            if target.vcp == VCP.brightness { return ("sun.max.fill", .orange) }
            if target.vcp == VCP.contrast { return ("circle.lefthalf.filled", .gray) }
            return ("slider.horizontal.3", .teal)
        case .nightShift: return ("moon.fill", .indigo)
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
            SymbolTile(symbol: symbol.0, color: symbol.1).padding(.top, 2)
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
                Text(change.why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(change.title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(action: toggleDone) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3)
                        .foregroundStyle(done ? Color.green : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
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
                    Image(systemName: expanded ? "chevron.up" : "info.circle")
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
        .padding(.horizontal, 14).padding(.vertical, 10)
        .opacity(done ? 0.6 : 1)
    }
}
