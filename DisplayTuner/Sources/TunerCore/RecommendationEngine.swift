import Foundation

/// The state of everything around one display that affects its settings.
public struct EngineContext: Sendable {
    /// Kept for saved presets; brightness no longer depends on it.
    public var lighting: RoomLighting
    public var allDisplays: [DisplayFacts]
    /// Night Shift's current state, or nil if it can't be read on this Mac.
    public var nightShiftEnabled: Bool?
    /// Switchboard dims below a monitor's minimum through the colour table.
    public var switchboardInstalled: Bool

    public init(lighting: RoomLighting, allDisplays: [DisplayFacts], nightShiftEnabled: Bool? = nil,
                switchboardInstalled: Bool = false) {
        self.lighting = lighting
        self.allDisplays = allDisplays
        self.nightShiftEnabled = nightShiftEnabled
        self.switchboardInstalled = switchboardInstalled
    }
}

/// Turns the research (the knowledge base) and what the monitor reports about
/// itself into changes and instructions for one preset. Only the Acer Nitro
/// XV272K V5 gets recommendations; every other screen is left alone.
public enum RecommendationEngine {
    public static func recommend(_ useCase: UseCase, for display: DisplayFacts, context: EngineContext) -> Recommendation {
        guard let profile = KnowledgeBase.match(name: display.name, vendorID: display.vendorID) else {
            return Recommendation(
                useCase: useCase, displayID: display.id, profile: nil,
                headline: "Not supported",
                changes: [], manualSteps: [], warnings: [],
                notes: ["Display Tuner is built for the Acer Nitro XV272K V5 and leaves this screen alone."],
                modeOptions: [], sources: [])
        }
        var builder = Builder(useCase: useCase, display: display, context: context, profile: profile)
        builder.planMode()
        builder.planRefreshExtras()
        builder.planColour()
        if !display.hasCalibration { builder.planBrightness() }
        builder.planNightShift()
        builder.planMonitorMenu()
        builder.planHDR()
        builder.planApps()
        return builder.result()
    }

    private struct Builder {
        let useCase: UseCase
        let display: DisplayFacts
        let context: EngineContext
        let profile: MonitorProfile

        var changes: [PlannedChange] = []
        var steps: [ManualStep] = []
        var warnings: [String] = []
        var notes: [String] = []
        var modeOptions: [DisplayMode] = []
        var usedSources: [Source] = []
        var targetMode: DisplayMode?

        init(useCase: UseCase, display: DisplayFacts, context: EngineContext, profile: MonitorProfile) {
            self.useCase = useCase
            self.display = display
            self.context = context
            self.profile = profile
        }

        var ddcValues: [UInt8: VCPValue] { display.ddc.values }

        var isWideGamut: Bool { display.primaries?.isWideGamut ?? profile.specs.isWideGamut }

        /// A ColorSync profile someone assigned by hand (e.g. from a colorimeter),
        /// as opposed to one of the standard system profiles.
        var hasCalibrationProfile: Bool {
            guard let path = display.customProfilePath else { return false }
            return !path.hasPrefix("/System/Library/ColorSync/Profiles/")
        }

        /// Wants the panel's full backlight.
        var wantsFullBrightness: Bool { useCase == .maxBrightness || useCase == .macbookLook }

        mutating func sources(_ ids: [String]) -> [Source] {
            let found = ids.compactMap { id in profile.source(id) ?? KnowledgeBase.generalSource(id) }
            for source in found where !usedSources.contains(source) { usedSources.append(source) }
            return found
        }

        mutating func step(_ place: ManualStep.Place, _ setting: String, _ value: String, path: String, why: String, sources ids: [String] = []) {
            guard !steps.contains(where: { $0.place == place && $0.setting == setting }) else { return }
            steps.append(ManualStep(place: place, setting: setting, value: value, path: path, why: why, sources: sources(ids)))
        }

        // MARK: Resolution and refresh rate

        mutating func planMode() {
            if let master = display.mirrorOf {
                let masterName = context.allDisplays.first { $0.id == master }?.name ?? "another screen"
                notes.append("Mirrors \(masterName), so its resolution and refresh rate follow that screen.")
                return
            }
            guard !display.modes.isEmpty else { return }
            modeOptions = ModePicker.menuModes(display.modes)

            let current = display.currentMode
            let recommendedLayout = ModePicker.recommendedLayout(display.modes, widthMM: display.widthMM)
            let currentIsSharp = current.map { ModePicker.isSharp($0.layout, in: display.modes) } ?? false
            // Keep the desktop size the person chose if it's drawn at or above
            // the panel's resolution; switching presets shouldn't resize everything.
            guard let layout = currentIsSharp ? current?.layout : recommendedLayout else { return }

            let policy: ModePicker.RefreshPolicy = useCase == .videoEditing ? .videoFriendly : .highest
            guard let target = ModePicker.bestMode(for: layout, in: display.modes, policy: policy) else { return }
            targetMode = target

            var why = refreshReason(target)
            if !currentIsSharp, let current {
                why += " \(current.layout.label) is drawn below the panel's native resolution and scaled up by the monitor, so this also moves to \(layout.label)."
            }
            if let ideal = recommendedLayout, ideal != layout,
               let ppi = ModePicker.pointsPerInch(ideal, widthMM: display.widthMM) {
                notes.append("On this screen, \(ideal.label) gives about \(Int(ppi.rounded())) points per inch, the closest to Apple's Studio Display at its default size (218 pixels per inch at 2×, so 109). You can pick it in the mode list.")
                _ = sources(["apple-studio-display"])
            }
            if useCase == .macbookLook { noteRetinaDensity() }

            if current.map({ !$0.matches(target) }) ?? true {
                changes.append(PlannedChange(
                    id: "mode",
                    change: .mode(target),
                    title: "Resolution & refresh rate",
                    detail: "\(current?.label ?? "Unknown") → \(target.label)",
                    why: why,
                    onByDefault: true))
            }
        }

        /// The panel's pixel density next to a MacBook Air's.
        mutating func noteRetinaDensity() {
            guard let native = ModePicker.nativePixelSize(display.modes), let mm = display.widthMM, mm > 50 else { return }
            let ppi = Double(native.width) / (mm / 25.4)
            notes.append("A MacBook Air (M4) has 224 pixels per inch; this panel has about \(Int(ppi.rounded())). That difference is in the hardware, so text up close stays a little less fine than on the MacBook.")
            _ = sources(["apple-macbook-air-m4"])
        }

        func refreshReason(_ mode: DisplayMode) -> String {
            let hz = mode.refreshRate
            guard hz > 0 else { return "The fastest mode this display offers at this size." }
            switch useCase {
            case .videoEditing:
                let fits = [24.0, 25, 30].filter { hz.rounded().truncatingRemainder(dividingBy: $0) == 0 }.map { String(Int($0)) }
                if fits.isEmpty { return "No rate here divides evenly by common frame rates, so this is the fastest." }
                return "\(DisplayMode.hz(hz)) Hz divides evenly by \(fits.joined(separator: ", ")) fps footage. Apple: \"Choose a refresh rate that divides evenly into the frame rate of your content.\""
            case .competitiveGaming:
                return String(format: "The highest rate at full resolution: a new frame every %.1f ms, against 16.7 ms at 60 Hz.", 1000 / hz)
            default:
                return "The highest rate this display offers at the current size."
            }
        }

        mutating func planRefreshExtras() {
            guard display.mirrorOf == nil, !display.isBuiltIn else { return }

            for mirror in context.allDisplays where mirror.mirrorOf == display.id && mirror.maxRefresh > 0 {
                notes.append("\(mirror.name) mirrors this screen and supports up to \(DisplayMode.hz(mirror.maxRefresh)) Hz.")
            }

            if useCase == .competitiveGaming, let fast = ModePicker.fastLowResolutionMode(display.modes) {
                notes.append("\(fast.label) is available: half the resolution for twice the refresh rate. Choose it in the mode list after turning DFR on.")
            }

            switch useCase {
            case .videoEditing:
                if let target = targetMode {
                    step(.systemSettings, "Refresh Rate", "\(DisplayMode.hz(target.refreshRate)) Hz (not Variable)",
                         path: "System Settings → Displays → \(display.name) → Refresh Rate",
                         why: "Apple: \"Choose a refresh rate that divides evenly into the frame rate of your content.\" A variable rate follows the source instead.",
                         sources: ["apple-frame-rate"])
                }
            case .photoEditing:
                break
            default:
                step(.systemSettings, "Refresh Rate", "Variable (or Adaptive)",
                     path: "System Settings → Displays → \(display.name) → Refresh Rate",
                     why: "Adaptive-Sync lets the refresh rate follow the frame rate. Apple: \"Choose Variable or Adaptive from the Refresh Rate pop-up menu. To stop using Adaptive Sync, choose one of the fixed refresh rates instead.\" Set it after applying here, because the app selects a fixed rate.",
                     sources: ["apple-vrr"])
            }
            step(.hardware, "Cable", "USB-C / Thunderbolt to DisplayPort",
                 path: "Mac mini Thunderbolt port → monitor DisplayPort or USB-C",
                 why: "Acer supports 4K at 160 Hz over DisplayPort or USB-C. Apple, for Adaptive Sync: \"Do not use an HDMI cable or adapter.\"",
                 sources: ["acer-manual-xv275k", "apple-vrr"])
        }

        // MARK: Colour

        mutating func planColour() {
            if hasCalibrationProfile {
                let name = display.profileName ?? (display.customProfilePath.map { ($0 as NSString).lastPathComponent } ?? "a custom profile")
                notes.append("\(name) is assigned to this screen, probably from a calibration, so the app leaves the colour profile alone.")
                return
            }

            let currentlySRGB = display.customProfilePath?.hasSuffix(ProfileChoice.sRGBFile) ?? false
            let currentLabel = display.customProfilePath == nil ? "Display's own profile" : (display.profileName ?? "Custom")

            if useCase.isEditing && profile.specs.hasSRGBColorSpace {
                if !currentlySRGB {
                    changes.append(PlannedChange(
                        id: "profile",
                        change: .colorProfile(.system(ProfileChoice.sRGBFile)),
                        title: "Colour profile",
                        detail: "\(currentLabel) → sRGB",
                        why: "Pairs with the monitor's sRGB colour space (Menu → Color → Color Space → sRGB, see the checklist), so macOS treats the screen as the sRGB it then shows. The XV272K V3 measured an average ΔE00 of 1.03 there.",
                        onByDefault: true))
                    _ = sources(["danawa-xv272kv3"])
                }
            } else if display.customProfilePath != nil {
                changes.append(PlannedChange(
                    id: "profile", change: .colorProfile(.factory), title: "Colour profile",
                    detail: "\(currentLabel) → Display's own profile",
                    why: "Pairs with Color Space General, the panel's native colour (see the checklist). The display's own profile is the one macOS made for it.",
                    onByDefault: true))
            }

            if useCase == .macbookLook {
                if isWideGamut {
                    notes.append("A MacBook Air (M4) has a 500-nit, P3 wide-colour display. With Color Space General and the display's own profile, this panel shows P3 content in its wide gamut too; the XV272K V3 covered 94.5% of P3.")
                    _ = sources(["apple-macbook-air-m4", "danawa-xv272kv3"])
                } else {
                    warnings.append("macOS reports this screen's gamut as about sRGB, so it can't show the extra P3 colour a MacBook's display has.")
                }
            }
        }

        // MARK: Brightness

        mutating func planBrightness() {
            guard let brightness = ddcValues[VCP.brightness] else {
                if case .unavailable = display.ddc, display.mirrorOf == nil {
                    notes.append("The monitor isn't answering DDC/CI, so brightness has to be set with its own buttons. Check Menu → System → DDC/CI is On.")
                }
                return
            }
            if wantsFullBrightness {
                if brightness.percent < 100 {
                    let why = (useCase == .macbookLook ? "A MacBook Air reaches 500 nits; full backlight is as close as this panel gets. " : "Full backlight. ")
                        + "On an LCD the backlight lifts white and black together, so the contrast ratio stays about the same (RTINGS). The XV272K V3 measured 388.7 cd/m² at Brightness 100. Turn Max Brightness On in the Picture menu as well, or the backlight stays capped."
                    changes.append(PlannedChange(
                        id: "ddc-brightness",
                        change: .ddc(DDCTarget(vcp: VCP.brightness, value: .percent(100))),
                        title: "Brightness",
                        detail: "\(brightness.percent)% → 100%",
                        why: why,
                        onByDefault: true))
                    _ = sources(["rtings-contrast", "danawa-xv272kv3", "pcmonitors-xv282k"])
                }
            } else if useCase == .photoEditing {
                notes.append("The app doesn't set an editing brightness: the V5's brightness curve isn't published (the XV272K V3 measured 40.1 cd/m² at Brightness 0 and 388.7 at 100), so a percentage can't be turned into cd/m². Common targets are about 120 cd/m² for editing (Canon) and 80–120 for print work (Photo Review); the sRGB reference is 80 (W3C). A colorimeter gives the exact setting.")
                _ = sources(["danawa-xv272kv3", "canon-brightness", "photoreview-prints", "w3c-srgb"])
            } else if useCase == .videoEditing {
                notes.append("The app doesn't set a grading brightness: the V5's brightness curve isn't published, so a percentage can't be turned into cd/m². ITU-R BT.2035 puts reference white at 100 cd/m² in a 10 lux room. A colorimeter gives the exact setting.")
                _ = sources(["itu-bt2035"])
            }

            if let contrast = ddcValues[VCP.contrast], contrast.percent != 50 {
                notes.append("Contrast is \(contrast.percent). The default measured on the sibling XV273K is 50, and calibrations of sibling models used 48–49. You can set it under Adjust.")
                _ = sources(["tftcentral-xv273k", "tomshw-xv272u"])
            }
        }

        // MARK: Night Shift

        mutating func planNightShift() {
            guard useCase.isEditing || useCase == .macbookLook, context.nightShiftEnabled == true else { return }
            changes.append(PlannedChange(
                id: "night-shift",
                change: .nightShift(enabled: false),
                title: "Night Shift",
                detail: "On → Off",
                why: "Apple: Night Shift \"shifts the colors of your display to the warmer end of the color spectrum\". Undo turns it back on.",
                onByDefault: true,
                isGlobal: true))
            _ = sources(["apple-night-shift"])
        }

        // MARK: Monitor menu

        mutating func planMonitorMenu() {
            if display.hasCalibration {
                notes.append("Calibration protected: keep the monitor's calibrated picture settings unchanged. Presets only change resolution, refresh rate and Night Shift.")
                return
            }
            guard display.mirrorOf == nil else { return }
            for item in profile.osd where item.useCases.contains(useCase) {
                step(.monitorMenu, item.setting, item.value, path: item.path, why: item.why, sources: item.sourceIDs)
            }
        }

        // MARK: HDR

        mutating func planHDR() {
            guard display.mirrorOf == nil else { return }
            step(.systemSettings, "High Dynamic Range",
                 useCase == .immersiveGaming ? "Off, except for HDR games and video" : "Off",
                 path: "System Settings → Displays → \(display.name) → High Dynamic Range",
                 why: "Apple: the setting \"appears only on third-party displays that support HDR10\", and \"If you don't want to use HDR on your external display, turn this setting off.\" The XV272K V3 peaked at 332 cd/m² in HDR, below its 388.7 cd/m² SDR maximum.",
                 sources: ["apple-hdr", "danawa-xv272kv3"])
        }

        // MARK: Apps

        mutating func planApps() {
            if useCase.isEditing && context.switchboardInstalled && display.ddc.isAvailable {
                step(.apps, "Switchboard brightness", "Keep it above the monitor's own minimum",
                     path: "Switchboard → Brightness",
                     why: "Below the monitor's minimum, Switchboard dims through the colour table. TFTCentral advises against dimming at the graphics-card level, \"which can reduce contrast ratio\".",
                     sources: ["tftcentral-xv273k"])
            }
        }

        mutating func result() -> Recommendation {
            notes.append(contentsOf: profile.notes)
            return Recommendation(
                useCase: useCase,
                displayID: display.id,
                profile: profile,
                headline: useCase.subtitle,
                changes: changes,
                manualSteps: steps,
                warnings: warnings,
                notes: notes,
                modeOptions: modeOptions,
                sources: usedSources)
        }
    }
}
