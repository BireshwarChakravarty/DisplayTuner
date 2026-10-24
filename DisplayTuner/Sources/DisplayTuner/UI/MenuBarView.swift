import AppKit
import SwiftUI
import TunerCore

/// The menu-bar panel, laid out like Control Center: the screens and what
/// they're set to, one-tap presets, a live brightness slider and quick toggles.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AutoSwitchSettings.enabledKey) private var autoEnabled = false
    @State private var message: String?
    @State private var pendingPreset: UseCase?

    private var externals: [DisplayFacts] { model.displays.filter { !$0.isBuiltIn } }
    private var mainDisplay: DisplayFacts? {
        externals.first { $0.mirrorOf == nil && $0.isSupported }
    }
    private var canTap: Bool { model.canChange || model.isDemo }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let auto = model.autoState { autoBanner(auto) }
            screensModule
            presetsModule
            if let display = mainDisplay, !display.isBuiltIn { BrightnessModule(display: display) }
            toggleTiles
            footer
        }
        .padding(12)
        .frame(width: 368)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            AppMark().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Gamut Pro").font(.headline)
                Text(headline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small).padding(.trailing, 4) }
            CircleButton(symbol: "gearshape", help: "Settings") {
                openSettings()
                NSApp.activate()
            }
            CircleButton(symbol: "macwindow", help: "Open Gamut Pro") { showWindow() }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var headline: String {
        if model.isBusy { return "Applying…" }
        if model.confirmation != nil { return "Confirm the new mode in the window" }
        guard let display = mainDisplay else { return "Acer XV272K V5 not connected" }
        let refresh = display.currentMode.map { " · \($0.refreshLabel)" } ?? ""
        return "\(model.useCase(for: display.id).title)\(refresh)"
    }

    private func autoBanner(_ auto: AutoState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars").foregroundStyle(.orange)
            Text("\(auto.useCase.title) while \(auto.appName) is in front")
                .font(.caption).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Screens

    private var screensModule: some View {
        Module {
            VStack(spacing: 10) {
                if externals.isEmpty {
                    Label("No external display connected", systemImage: "display.trianglebadge.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(externals) { display in
                    ScreenRow(display: display, useCase: model.useCase(for: display.id),
                              mirroring: display.mirrorOf.flatMap { id in model.displays.first { $0.id == id }?.name },
                              faster: model.fasterMode(for: display), enabled: model.canChange) { faster in
                        Task {
                            await model.applyRefreshOnly(faster, for: display)
                            if model.confirmation != nil { showWindow() }
                        }
                    }
                }
            }
        }
    }


    // MARK: Presets

    private var presetsModule: some View {
        Module {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Presets").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(mainDisplay?.name ?? "").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), alignment: .center, spacing: 10) {
                    ForEach(UseCase.allCases) { useCase in
                        PresetButton(useCase: useCase, selected: isCurrent(useCase),
                                     working: pendingPreset == useCase) {
                            Task { await choose(useCase) }
                        }
                        .disabled(!canTap || mainDisplay == nil)
                        .frame(maxWidth: .infinity)
                    }
                }
                if let line = message ?? currentSummary {
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
        }
    }

    private var currentSummary: String? {
        guard let display = mainDisplay else { return nil }
        return model.useCase(for: display.id).subtitle
    }

    private func isCurrent(_ useCase: UseCase) -> Bool {
        mainDisplay.map { model.useCase(for: $0.id) == useCase } ?? false
    }

    private func choose(_ useCase: UseCase) async {
        pendingPreset = useCase
        message = nil
        let results = await model.quickApply(useCase)
        pendingPreset = nil
        if model.confirmation != nil { showWindow(); return }
        let failed = results.filter { !$0.ok }.count
        let done = results.count - failed
        let steps = mainDisplay.map { model.recommendation(for: $0).manualSteps.filter { $0.place == .monitorMenu }.count } ?? 0
        var parts: [String] = []
        if let waiting = model.results.first, waiting.title == "Waiting for the display" {
            withAnimation { message = waiting.message }
            return
        }
        if results.isEmpty { parts.append("\(useCase.title) is selected; nothing needed changing") }
        else { parts.append("\(useCase.title): \(done) change\(done == 1 ? "" : "s") made") }
        if failed > 0 { parts.append("\(failed) didn't take") }
        if steps > 0 { parts.append("\(steps) step\(steps == 1 ? "" : "s") on the monitor") }
        withAnimation { message = parts.joined(separator: " · ") }
    }

    // MARK: Toggles

    private var toggleTiles: some View {
        HStack(spacing: 10) {
            ToggleTile(symbol: "moon.fill", title: "Night Shift",
                       value: model.nightShiftEnabled.map { $0 ? "On" : "Off" } ?? "Unavailable",
                       on: model.nightShiftEnabled == true, tint: .orange) {
                if let on = model.nightShiftEnabled { model.setNightShiftNow(!on) }
            }
            .disabled(model.nightShiftEnabled == nil || model.isBusy || model.confirmation != nil)

            ToggleTile(symbol: "wand.and.stars", title: "Auto", value: autoEnabled ? "On" : "Off",
                       on: autoEnabled, tint: .accentColor) {
                model.setAutoSwitch(enabled: !autoEnabled, gamePreset: AutoSwitchSettings.gamePreset)
                autoEnabled = AutoSwitchSettings.isEnabled
            }
            .disabled(model.isDemo)
            .help("Switch presets for games and editing apps automatically.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button { Task { await model.undoLastApply() } } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(model.lastSnapshot == nil || !model.canChange)
            Spacer()
            Button("Open Gamut Pro") { showWindow() }
            Button {
                Task {
                    if model.confirmation != nil { await model.revertUnconfirmed() }
                    NSApp.terminate(nil)
                }
            } label: { Image(systemName: "power") }
            .help("Quit Gamut Pro")
            .accessibilityLabel("Quit Gamut Pro")
            .disabled(model.isBusy).keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

// MARK: - Pieces

/// A Control Center-style rounded module.
private struct Module<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

private struct CircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ScreenRow: View {
    let display: DisplayFacts
    let useCase: UseCase
    let mirroring: String?
    let faster: DisplayMode?
    let enabled: Bool
    let useFaster: (DisplayMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: mirroring != nil ? "rectangle.on.rectangle" : "display")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(mirroring != nil ? Color.secondary : Color.white)
                    .frame(width: 32, height: 32)
                    .background(mirroring != nil ? AnyShapeStyle(Color.primary.opacity(0.1)) : AnyShapeStyle(Color.accentColor.gradient),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if mirroring == nil {
                    Label(shortTitle(useCase), systemImage: useCase.symbol)
                        .font(.caption.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            if let faster, let current = display.currentMode {
                Button { useFaster(faster) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text("Running at \(current.refreshLabel)")
                        Spacer(minLength: 4)
                        Text("Use \(faster.refreshLabel)").fontWeight(.semibold)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundStyle(.primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
            }
        }
    }

    private var detail: String {
        if let mirroring { return "Mirroring \(mirroring)" }
        guard let mode = display.currentMode else { return "Connected" }
        return "\(mode.layout.width) × \(mode.layout.height) · \(mode.refreshLabel)"
    }
}

private func shortTitle(_ useCase: UseCase) -> String {
    switch useCase {
    case .competitiveGaming: return "Competitive"
    case .immersiveGaming: return "Immersive"
    case .photoEditing: return "Photo"
    case .videoEditing: return "Video"
    case .macbookLook: return "MacBook"
    case .maxBrightness: return "Max"
    case .everyday: return "Everyday"
    }
}

private struct PresetButton: View {
    let useCase: UseCase
    let selected: Bool
    let working: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.1)))
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: useCase.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                }
                .frame(width: 42, height: 42)
                .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear, radius: 6, y: 2)
                Text(shortTitle(useCase))
                    .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(useCase.title): \(useCase.subtitle)")
        .accessibilityLabel(useCase.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The main monitor's backlight, set live over DDC/CI as the slider moves.
private struct BrightnessModule: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts
    @State private var dragging: Double?

    private var level: VCPValue? { display.ddc.values[VCP.brightness] }

    var body: some View {
        Module {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Brightness").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if level != nil {
                    ThickSlider(value: Binding(
                        get: { dragging ?? Double(level?.percent ?? 0) },
                        set: { value in
                            dragging = value
                            model.setBrightnessLive(value, for: display)
                        }),
                        onEnd: { dragging = nil })
                    .disabled(!model.canSetBrightnessLive(display))
                    if display.hasCalibration {
                        Text("Calibrated: hardware levels are left as they are.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Label(display.ddc == .probing ? "Reading the monitor…" : "This monitor doesn't take brightness over DDC/CI. Use its buttons.",
                          systemImage: display.ddc == .probing ? "ellipsis" : "hand.point.up.left")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var readout: String {
        let percent = dragging.map { Int($0.rounded()) } ?? level?.percent
        guard let percent else { return display.name }
        return "\(percent)%"
    }
}

/// A Control Center-style slider: a thick capsule that fills from the left.
private struct ThickSlider: View {
    @Binding var value: Double
    var onEnd: () -> Void = {}
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = min(max(value / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor.opacity(isEnabled ? 1 : 0.4))
                    .frame(width: max(30, 30 + (width - 30) * fraction))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.leading, 9)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .opacity(fraction > 0.9 ? 0 : 1)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard isEnabled, width > 0 else { return }
                    value = (min(max(drag.location.x / width, 0), 1) * 100).rounded()
                }
                .onEnded { _ in onEnd() })
        }
        .frame(height: 30)
        .focusable()
        .onKeyPress(.leftArrow) { value = max(0, value - 5); onEnd(); return .handled }
        .onKeyPress(.rightArrow) { value = min(100, value + 5); onEnd(); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value.rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(100, value + 5)
            case .decrement: value = max(0, value - 5)
            @unknown default: break
            }
            onEnd()
        }
    }
}

private struct ToggleTile: View {
    let symbol: String
    let title: String
    let value: String
    let on: Bool
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(on ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.1)), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(value).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(value)
    }
}
