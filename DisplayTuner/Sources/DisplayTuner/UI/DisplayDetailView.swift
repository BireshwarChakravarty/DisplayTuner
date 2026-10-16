import SwiftUI
import TunerCore

struct DisplayDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let display: DisplayFacts
    @ViewState private var tab = ProcessInfo.processInfo.arguments.contains("--controls") ? "Fine-tune"
        : ProcessInfo.processInfo.arguments.contains("--research") ? "Research" : "Overview"
    @ViewState private var savingPreset = false
    @ViewState private var presetName = ""
    private var rec: Recommendation { model.recommendation(for: display) }
    private var changes: [PlannedChange] { model.changes(for: display) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let insight { insightBanner(insight) }
                metrics
                HStack {
                    Picker("Section", selection: $tab) {
                        Text("Overview").tag("Overview")
                        Text("Fine-tune").tag("Fine-tune")
                        Text("Research").tag("Research")
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    if display.hasCalibration { Label("Calibration protected", systemImage: "lock.shield.fill").font(.caption).foregroundStyle(Color.studioCyan) }
                }
                if tab == "Overview" {
                    presets
                    recommendations
                    manualSteps
                } else if tab == "Fine-tune" {
                    controls
                    recommendations
                } else {
                    research
                }
                if !model.results.isEmpty { resultList }
                restoreBar
            }.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 110) // clear of the floating Apply bar
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { applyDock }
        .alert("Save a studio preset", isPresented: $savingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { model.savePreset(name: presetName, display: display); presetName = "" }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Save this activity, room lighting, display mode and hardware levels. Loading a preset always lets you review before applying.") }
        .onChange(of: display.id) { _, _ in tab = "Overview" }
    }

    /// The fastest mode at the current desktop size, when the display is running slower.
    private var fasterMode: DisplayMode? {
        guard display.mirrorOf == nil, let current = display.currentMode,
              let best = ModePicker.bestMode(for: current.layout, in: display.modes, policy: .highest),
              best.refreshRate > current.refreshRate + 1 else { return nil }
        return best
    }

    private struct Insight { var text: String; var action: String?; var mode: DisplayMode? }

    private var insight: Insight? {
        if let faster = fasterMode, let current = display.currentMode {
            return Insight(text: "Running at \(current.refreshLabel). This display does \(faster.refreshLabel) at the same size: smoother motion and lower input lag at no cost to sharpness.",
                           action: "Use \(faster.refreshLabel)", mode: faster)
        }
        if let master = display.mirrorOf, let source = model.displays.first(where: { $0.id == master }) {
            return Insight(text: "Mirroring \(source.name). Its resolution, refresh rate and colour follow that screen; set brightness with this display's own buttons.", action: nil, mode: nil)
        }
        return nil
    }

    private func insightBanner(_ insight: Insight) -> some View {
        HStack(spacing: 14) {
            Image(systemName: insight.mode != nil ? "bolt.fill" : "rectangle.on.rectangle").font(.system(size: 15)).foregroundStyle(insight.mode != nil ? Color.orange : Color.studioCyan)
            Text(insight.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action = insight.action, let mode = insight.mode {
                Button(action) {
                    model.chooseMode(mode, for: display)
                    tab = "Overview"
                }.buttonStyle(StudioButton()).disabled(!model.canChange)
            }
        }.padding(.horizontal, 18).padding(.vertical, 14)
            .background((insight.mode != nil ? Color.orange : Color.studioCyan).opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder((insight.mode != nil ? Color.orange : Color.studioCyan).opacity(0.25)))
    }

    private var hero: some View {
        HStack(spacing: 26) {
            MonitorPortrait(display: display).scaleEffect(0.72).frame(width: 220, height: 150)
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    StatusPill(text: display.mirrorOf != nil ? "MIRRORED" : display.isBuiltIn ? "BUILT-IN" : "EXTERNAL")
                    StatusPill(text: model.useCase(for: display.id).title.uppercased(), color: .studioViolet)
                    if let auto = model.autoState { StatusPill(text: "AUTO · \(auto.appName.uppercased())", color: .orange) }
                    if rec.profile != nil { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.studioCyan).help("Model matched in research database") }
                }
                Text(display.name).font(.system(size: 22, weight: .semibold)).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
                Text(rec.profile?.specs.size.appending("  ·  ").appending(rec.profile?.specs.panel.rawValue ?? "") ?? "Connected display")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(display.currentMode?.label ?? "Current mode unavailable")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Button { model.identify(display) } label: { Label("Identify", systemImage: "scope") }.buttonStyle(.plain).disabled(model.isDemo)
                    Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!) } label: { Label("Display settings", systemImage: "arrow.up.right") }.buttonStyle(.plain)
                    Button { savingPreset = true } label: { Label("Save preset", systemImage: "plus") }.buttonStyle(.plain)
                        .disabled(model.isBusy || model.confirmation != nil || model.isDemo)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(Color.studioCyan).padding(.top, 3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 22).padding(.vertical, 16)
            .background(LinearGradient(colors: [Color.studioCyan.opacity(0.065), Color.studioViolet.opacity(0.045), Color.primary.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(LinearGradient(colors: [.studioCyan.opacity(0.2), .white.opacity(0.04), .studioViolet.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metric("RESOLUTION", display.nativePixels.map { "\($0.width) × \($0.height)" } ?? "Unknown", "display", "Largest reported mode")
            metric("REFRESH RATE", display.currentMode?.refreshLabel ?? "Unknown", "waveform.path",
                   fasterMode.map { "\($0.refreshLabel) available at this size" } ?? "Fastest at this size", warn: fasterMode != nil)
            metric("COLOUR GAMUT", display.primaries.map { "\(Int(($0.coverage(of: .displayP3) * 100).rounded()))% P3" } ?? "Unknown", "circle.hexagongrid",
                   display.primaries.map { "\(Int(($0.coverage(of: .sRGB) * 100).rounded()))% sRGB · from the active profile" } ?? "From the active ICC profile")
            metric("HARDWARE", display.ddc.isAvailable ? "Connected" : ddcLabel, "slider.horizontal.3",
                   display.capabilities.map { "\($0.describedControls.count) controls reported over DDC/CI" } ?? (display.ddc.isAvailable ? "DDC/CI controls available" : "Use monitor buttons"))
        }
    }

    private var ddcLabel: String {
        switch display.ddc { case .probing, .unknown: return "Scanning…"; case .unavailable: return "Manual"; case .available: return "Connected" }
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ detail: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Eyebrow(text: title); Spacer(minLength: 0); Image(systemName: icon).foregroundStyle((warn ? Color.orange : Color.studioCyan).opacity(0.75)).font(.system(size: 12)) }
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(warn ? Color.orange : Color.primary).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.05)))
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set the scene.").font(.system(size: 19, weight: .semibold))
                    Text("Pick what you’re doing. We’ll take care of the details.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("ROOM").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                Picker("Room lighting", selection: $model.lighting) {
                    ForEach(RoomLighting.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize().disabled(model.isBusy || model.confirmation != nil)
            }
            HStack(spacing: 9) {
                ForEach(UseCase.allCases) { useCase in
                    PresetTile(useCase: useCase, selected: model.useCase(for: display.id) == useCase) { model.setUseCase(useCase, for: display.id) }
                }
            }.disabled(model.isBusy || model.confirmation != nil)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Dial it in.").font(.title2.bold())
            Text("Stage your adjustments here, then Apply. Every change is saved for Undo.").font(.callout).foregroundStyle(.secondary)
            if display.hasCalibration {
                Label("Hardware levels are locked to protect your calibration.", systemImage: "lock.shield.fill").foregroundStyle(Color.studioCyan)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    hardwareSlider(vcp: VCP.brightness, icon: "sun.max", title: "Brightness")
                    hardwareSlider(vcp: VCP.contrast, icon: "circle.lefthalf.filled", title: "Contrast")
                }
            }
            StudioCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Resolution & refresh rate", systemImage: "display").font(.headline)
                    if rec.modeOptions.isEmpty { Text("This display follows the screen it mirrors, or has no selectable modes.").font(.callout).foregroundStyle(.secondary) }
                    else {
                        Picker("Mode", selection: Binding(get: { model.pickerMode(for: display) }, set: { if let mode = $0 { model.chooseMode(mode, for: display) } })) {
                            ForEach(rec.modeOptions) { Text($0.label).tag(Optional($0)) }
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                        Text("Resolution changes include a 15-second confirmation and automatic rollback.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.disabled(model.isBusy || model.confirmation != nil)
    }

    private func hardwareSlider(vcp: UInt8, icon: String, title: String) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Label(title, systemImage: icon).font(.headline); Spacer(); Text("\(Int(sliderValue(vcp)))% ").font(.system(size: 23, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(Color.studioCyan) }
                Slider(value: Binding(get: { sliderValue(vcp) }, set: { value in
                    if vcp == VCP.brightness { model.manualBrightness[display.id] = value.rounded() } else { model.manualContrast[display.id] = value.rounded() }
                }), in: 0...100).disabled(display.ddc.values[vcp] == nil)
                Text(display.ddc.values[vcp] == nil ? "Unavailable over DDC/CI. Use this monitor’s buttons." : "Monitor hardware control · staged until Apply")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sliderValue(_ vcp: UInt8) -> Double {
        (vcp == VCP.brightness ? model.manualBrightness[display.id] : model.manualContrast[display.id]) ?? Double(display.ddc.values[vcp]?.percent ?? 0)
    }

    private var recommendations: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Your tuning plan", systemImage: "wand.and.stars").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(changes.filter { model.isOn($0, for: display) }.count) SELECTED").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Color.studioCyan)
                }
                if changes.isEmpty {
                    Label("You’re already set for this activity.", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Color.studioCyan)
                }
                ForEach(changes) { change in
                    Toggle(isOn: Binding(get: { model.isOn(change, for: display) }, set: { model.setOn($0, change, for: display) })) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(change.title).font(.system(size: 12, weight: .semibold))
                                if change.isExperimental { Text("EXPERIMENTAL").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
                                if change.isGlobal { Text("ALL SCREENS").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                                Spacer()
                                Text(change.detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.studioCyan).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            Text(change.why).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 5)
                    }.toggleStyle(.checkbox).disabled(model.isBusy || model.confirmation != nil)
                }
                ForEach(rec.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var manualSteps: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("A little hands-on.").font(.system(size: 18, weight: .semibold)); Spacer(); Text("MONITOR & APP SETTINGS").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary) }
            Text("These settings need your monitor’s buttons, System Settings, or your editing app.").font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(rec.manualSteps) { step in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.studioCyan)
                        Text(step.why).font(.callout).foregroundStyle(.secondary)
                        ForEach(step.sources) { source in
                            if let url = URL(string: source.url) { Link(source.title, destination: url).font(.caption) }
                        }
                    }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack { Text(step.setting).font(.system(size: 11, weight: .medium)); Spacer(); Text(step.value).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }.padding(13).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var research: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("The reasoning behind the pixels.").font(.title2.bold())
            if let profile = rec.profile {
                StudioCard { VStack(alignment: .leading, spacing: 10) {
                    Label(profile.displayName, systemImage: "books.vertical").font(.headline)
                    Text(profile.confidence).font(.callout).foregroundStyle(.secondary)
                } }
            }
            if let caps = display.capabilities {
                StudioCard { VStack(alignment: .leading, spacing: 10) {
                    Label("What this monitor reports", systemImage: "cpu").font(.headline)
                    Text(caps.describedControls.joined(separator: "  ·  ")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Read over DDC/CI\(caps.model.map { " from \($0)" } ?? "")\(caps.mccsVersion.map { ", MCCS \($0)" } ?? ""). Hardware changes are only offered for controls listed here.")
                        .font(.caption).foregroundStyle(.tertiary)
                } }
            }
            ForEach(rec.notes, id: \.self) { note in Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            StudioCard { VStack(alignment: .leading, spacing: 12) {
                Text("Sources & further reading").font(.headline)
                ForEach(sources) { source in
                    if let url = URL(string: source.url) { Link(destination: url) { HStack { Text(source.title).font(.callout); Spacer(); Image(systemName: "arrow.up.right").font(.caption) } } }
                }
            } }
            Text("Gamut is estimated from the active ICC profile, not a measurement. Brightness estimates use rated panel luminance. A colorimeter is required for reference accuracy.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sources: [Source] {
        var seen = Set<String>()
        return ((rec.profile?.sources ?? []) + rec.sources).filter { seen.insert($0.url).inserted }
    }

    private var resultList: some View {
        StudioCard { VStack(alignment: .leading, spacing: 12) {
            Text("Last operation").font(.headline)
            ForEach(model.results) { result in
                Label { VStack(alignment: .leading, spacing: 4) {
                    Text(result.title).font(.system(size: 11, weight: .semibold))
                    Text(result.message).font(.system(size: 10)).foregroundStyle(.secondary)
                } } icon: { Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(result.ok ? Color.studioCyan : .orange) }
            }
        } }
    }

    private var restoreBar: some View {
        HStack(spacing: 16) {
            Button { Task { await model.undoLastApply() } } label: { Label("Undo last apply", systemImage: "arrow.uturn.backward") }.disabled(model.lastSnapshot == nil || !model.canChange)
            Button { Task { await model.restoreOriginals() } } label: { Label("Restore originals", systemImage: "clock.arrow.circlepath") }.disabled(model.originalSnapshot == nil || !model.canChange)
            Spacer()
            Button { model.exportDiagnostics() } label: { Image(systemName: "square.and.arrow.up") }.help("Export diagnostics")
        }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 4)
    }

    private var dockInk: Color { colorScheme == .dark ? .white : .black }
    private var dockFill: Color { colorScheme == .dark ? Color(red: 0.075, green: 0.09, blue: 0.12) : .white }

    private var applyDock: some View {
        StudioGlassGroup {
            HStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 18)).foregroundStyle(Color.studioCyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isDemo ? "Explore your next display setup" : model.isBusy ? "Tuning your display…" : "Ready when you are.").font(.system(size: 12, weight: .semibold)).foregroundStyle(dockInk)
                    Text(model.isDemo ? "Demo workspace · no hardware changes" : "Original settings saved before every change.").font(.system(size: 10)).foregroundStyle(dockInk.opacity(0.65))
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button {
                    Task {
                        if model.recoveryRequired { await model.undoLastApply() }
                        else { await model.apply(to: [display.id]) }
                    }
                } label: { HStack(spacing: 10) { Text(model.recoveryRequired ? "Retry recovery" : "Apply changes"); Image(systemName: "arrow.right") } }
                    .buttonStyle(StudioButton(prominent: true))
                    .disabled(model.recoveryRequired ? model.isBusy : (!model.canChange || !changes.contains { model.isOn($0, for: display) }))
                    .keyboardShortcut(.return, modifiers: .command)
            }.padding(15).background(dockFill.opacity(0.96), in: RoundedRectangle(cornerRadius: 22)).modifier(StudioGlass(radius: 22)).padding(.horizontal, 28).padding(.bottom, 18).padding(.top, 8)
        }
    }
}

struct PresetTile: View {
    let useCase: UseCase
    let selected: Bool
    var action: () -> Void
    @ViewState private var hovered = false
    private var name: String {
        switch useCase { case .competitiveGaming: return "Competitive"; case .immersiveGaming: return "Immersive"; case .photoEditing: return "Photography"; case .videoEditing: return "Video editing"; case .everyday: return "Everyday" }
    }
    private var subtitle: String {
        switch useCase { case .competitiveGaming: return "Speed first"; case .immersiveGaming: return "Get lost in it"; case .photoEditing: return "True to life"; case .videoEditing: return "Frame perfect"; case .everyday: return "Find your flow" }
    }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Image(systemName: useCase.symbol).font(.system(size: 20, weight: .light)); Spacer(); if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)) } }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(.system(size: 9)).foregroundStyle(selected ? Color.studioCyan.opacity(0.7) : Color.secondary)
                }
            }.foregroundStyle(selected ? Color.studioCyan : Color.primary.opacity(0.7))
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).frame(height: 102)
                .background(selected ? Color.studioCyan.opacity(0.1) : Color.primary.opacity(hovered ? 0.065 : 0.025), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.studioCyan.opacity(0.55) : Color.primary.opacity(0.07)))
        }.buttonStyle(.plain).onHover { hovered = $0 }.accessibilityLabel(useCase.title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MonitorPortrait: View {
    let display: DisplayFacts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Ellipse().fill(Color.studioCyan.opacity(0.16)).frame(width: 250, height: 70).offset(y: 65)
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.12), Color(white: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.03, green: 0.09, blue: 0.15), Color(red: 0.05, green: 0.16, blue: 0.27), Color(red: 0.1, green: 0.06, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        AuroraWave().stroke(LinearGradient(colors: [.studioCyan, .blue, .studioViolet, .pink.opacity(0.75)], startPoint: .leading, endPoint: .trailing), lineWidth: 40).opacity(0.45).offset(y: 12)
                        AuroraWave().stroke(LinearGradient(colors: [.studioCyan.opacity(0.9), .studioViolet, .pink.opacity(0.8)], startPoint: .leading, endPoint: .trailing), lineWidth: 2).offset(y: 12)
                        VStack(spacing: 5) {
                            Text(display.mirrorOf != nil ? "MIRROR" : display.isBuiltIn ? "BUILT-IN" : "EXTERNAL DISPLAY").font(.system(size: 7, weight: .medium)).tracking(3).foregroundStyle(.white.opacity(0.5))
                            Text(display.nativePixels.map { $0.width >= 3840 ? "4K" : "HD" } ?? "HD").font(.system(size: 44, weight: .ultraLight, design: .rounded)).foregroundStyle(.white.opacity(0.9)).tracking(3)
                        }.offset(y: -15)
                    }.clipShape(RoundedRectangle(cornerRadius: 7)).padding(5).padding(.bottom, 7)
                    Circle().fill(Color.studioCyan.opacity(0.8)).frame(width: 2, height: 2).offset(y: 78)
                }.frame(width: 284, height: 170).shadow(color: .black.opacity(0.3), radius: 12, y: 8)
                Rectangle().fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.4), Color(white: 0.18)], startPoint: .leading, endPoint: .trailing)).frame(width: 27, height: 20)
                Capsule().fill(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)).frame(width: 100, height: 5)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Illustration of \(display.name)")
    }
}

struct AuroraWave: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: -20, y: rect.height * 0.7))
            p.addCurve(to: CGPoint(x: rect.width + 20, y: rect.height * 0.55), control1: CGPoint(x: rect.width * 0.3, y: rect.height * 1.15), control2: CGPoint(x: rect.width * 0.55, y: rect.height * 0.05))
        }
    }
}
