import Foundation

/// The state of everything around one display that affects its settings.
public struct EngineContext: Sendable {
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

/// Turns research (the knowledge base) and what a display reports about itself
/// into a concrete list of changes and instructions for one use case.
public enum RecommendationEngine {
    /// Rated SDR peak to assume for a monitor that isn't in the database.
    static let assumedPeakNits = 300.0

    public static func recommend(_ useCase: UseCase, for display: DisplayFacts, context: EngineContext) -> Recommendation {
        let profile = KnowledgeBase.match(name: display.name, vendorID: display.vendorID)
        var builder = Builder(useCase: useCase, display: display, context: context, profile: profile)
        builder.planMode()
        builder.planRefreshExtras()
        builder.planColour()
        builder.planBrightnessAndContrast()
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
        let profile: MonitorProfile?

        var changes: [PlannedChange] = []
        var steps: [ManualStep] = []
        var warnings: [String] = []
        var notes: [String] = []
        var modeOptions: [DisplayMode] = []
        var usedSources: [Source] = []
        var targetMode: DisplayMode?

        init(useCase: UseCase, display: DisplayFacts, context: EngineContext, profile: MonitorProfile?) {
            self.useCase = useCase
            self.display = display
            self.context = context
            self.profile = profile
        }

        var ddcValues: [UInt8: VCPValue] { display.ddc.values }

        var isWideGamut: Bool {
            display.primaries?.isWideGamut ?? profile?.specs.isWideGamut ?? false
        }

        /// A ColorSync profile someone assigned by hand (e.g. from a colorimeter),
        /// as opposed to one of the standard system profiles.
        var hasCalibrationProfile: Bool {
            guard let path = display.customProfilePath else { return false }
            return !path.hasPrefix("/System/Library/ColorSync/Profiles/")
        }

        mutating func sources(_ ids: [String]) -> [Source] {
            let found = ids.compactMap { id in profile?.source(id) ?? KnowledgeBase.generalSource(id) }
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
            // Keep the desktop size the person chose if it renders sharply;
            // switching presets shouldn't make everything jump in size.
            guard let layout = currentIsSharp ? current?.layout : recommendedLayout else { return }

            let policy: ModePicker.RefreshPolicy = useCase == .videoEditing ? .videoFriendly : .highest
            guard let target = ModePicker.bestMode(for: layout, in: display.modes, policy: policy) else { return }
            targetMode = target

            var why = refreshReason(target)
            if !currentIsSharp, let current {
                why += " \(current.layout.label) isn't a sharp size on this panel (the monitor has to stretch it), so this also moves to \(layout.label)."
            }
            if let ideal = recommendedLayout, ideal != layout,
               let ppi = ModePicker.pointsPerInch(ideal, widthMM: display.widthMM) {
                notes.append("For this screen size, \(ideal.label) is closest to the density macOS is designed for (≈\(Int(ppi.rounded())) points per inch). You can pick it in the mode list.")
            }

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

        func refreshReason(_ mode: DisplayMode) -> String {
            let hz = mode.refreshRate
            guard hz > 0 else { return "The fastest mode this display offers at this size." }
            let frame = 1000 / hz
            switch useCase {
            case .videoEditing:
                let fits = [24.0, 25, 30].filter { hz.rounded().truncatingRemainder(dividingBy: $0) == 0 }.map { String(Int($0)) }
                if fits.isEmpty { return "No rate here divides evenly by common frame rates, so this is the fastest." }
                return "\(DisplayMode.hz(hz)) Hz is a whole multiple of \(fits.joined(separator: ", ")) fps footage, so every frame is shown for the same time (no judder)."
            case .competitiveGaming:
                return String(format: "Highest rate at full resolution: a new frame every %.1f ms (16.7 ms at 60 Hz), so less motion blur and lower input lag.", frame)
            default:
                return "Highest rate at full resolution: smoother motion, scrolling and cursor, with no cost to sharpness."
            }
        }

        mutating func planRefreshExtras() {
            guard display.mirrorOf == nil, !display.isBuiltIn else { return }

            // Screens mirroring this one.
            let mirrors = context.allDisplays.filter { $0.mirrorOf == display.id }
            if let target = targetMode ?? display.currentMode {
                for mirror in mirrors where mirror.maxRefresh > 0 && mirror.maxRefresh + 1 < target.refreshRate {
                    let text = "\(mirror.name) mirrors this screen and tops out at \(DisplayMode.hz(mirror.maxRefresh)) Hz. Mirroring can hold this screen back or make motion stutter."
                    if useCase.isGaming {
                        warnings.append(text + " For gaming, switch \(mirror.name) off in Switchboard, or set it to Extend.")
                    } else {
                        notes.append(text)
                    }
                }
            }

            if useCase == .competitiveGaming, let fast = ModePicker.fastLowResolutionMode(display.modes) {
                notes.append("\(fast.label) is available for the lowest possible latency at half the resolution. Choose it in the mode list.")
            }

            let vrrKnown = profile?.specs.vrr != nil
            switch useCase {
            case .competitiveGaming, .immersiveGaming, .everyday:
                step(.systemSettings, "Refresh Rate", "Variable" + (vrrKnown ? "" : " (if listed)"),
                     path: "System Settings → Displays → \(display.name) → Refresh Rate",
                     why: "Adaptive-Sync matches the screen to the game's frame rate: no tearing, less stutter. Set it after applying here, because the app selects a fixed rate. If the screen flickers at low frame rates, go back to the fixed rate.",
                     sources: ["apple-vrr", "displaybuddy-flicker"])
                step(.hardware, "Cable", "USB-C / Thunderbolt to DisplayPort",
                     path: "Mac mini Thunderbolt port → monitor DisplayPort",
                     why: "Apple supports Adaptive-Sync over DisplayPort-capable connections and advises against HDMI for it.",
                     sources: ["apple-vrr"])
            case .videoEditing:
                if let target = targetMode {
                    step(.systemSettings, "Refresh Rate", "\(DisplayMode.hz(target.refreshRate)) Hz (not Variable)",
                         path: "System Settings → Displays → \(display.name) → Refresh Rate",
                         why: "A fixed multiple of the footage's frame rate gives even playback while you review edits.",
                         sources: ["apple-reference-modes"])
                }
            case .photoEditing:
                break
            }
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

            if useCase.isEditing {
                if profile?.specs.hasSRGBMode == true {
                    if !currentlySRGB {
                        changes.append(PlannedChange(
                            id: "profile",
                            change: .colorProfile(.system(ProfileChoice.sRGBFile)),
                            title: "Colour profile",
                            detail: "\(currentLabel) → sRGB",
                            why: "Pairs with the monitor's sRGB mode: macOS then knows the screen shows exactly sRGB, so colour-managed and unmanaged apps agree. Switch the monitor to sRGB mode at the same time (see Monitor menu).",
                            onByDefault: true))
                    }
                    if ddcValues[VCP.colorPreset] != nil {
                        changes.append(PlannedChange(
                            id: "ddc-preset",
                            change: .ddc(DDCTarget(vcp: VCP.colorPreset, value: .raw(ColorPreset.sRGB.rawValue))),
                            title: "Monitor colour preset over DDC",
                            detail: "→ sRGB (MCCS 0x14 = 0x01)",
                            why: "Some monitors switch to their sRGB mode when asked over DDC/CI. The app reads it back to check. If the monitor's menu doesn't show sRGB afterwards, set it by hand.",
                            onByDefault: false,
                            isExperimental: true))
                    }
                } else {
                    if display.customProfilePath != nil {
                        changes.append(PlannedChange(
                            id: "profile", change: .colorProfile(.factory), title: "Colour profile",
                            detail: "\(currentLabel) → Display's own profile",
                            why: "Without a hardware sRGB mode, the display's own profile is what tells colour-managed apps how its colours really look.",
                            onByDefault: true))
                    }
                    if isWideGamut {
                        warnings.append("This is a wide-gamut panel without a known sRGB mode. Colour-managed apps (Photoshop, Lightroom, Photos, Safari) are only as accurate as the profile macOS made from its EDID, and other apps will look oversaturated. Calibrating with a colorimeter is the only way to be exact.")
                    }
                    if ddcValues[VCP.colorPreset] != nil {
                        changes.append(PlannedChange(
                            id: "ddc-preset",
                            change: .ddc(DDCTarget(vcp: VCP.colorPreset, value: .raw(ColorPreset.k6500.rawValue))),
                            title: "White point over DDC",
                            detail: "→ 6500 K (MCCS 0x14 = 0x05)",
                            why: "D65 (6500 K) is the white point sRGB, Display P3 and Rec. 709 all assume.",
                            onByDefault: true))
                    }
                }
            } else {
                // Games and everyday use: the panel's full native gamut.
                if display.customProfilePath != nil {
                    changes.append(PlannedChange(
                        id: "profile", change: .colorProfile(.factory), title: "Colour profile",
                        detail: "\(currentLabel) → Display's own profile",
                        why: profile?.specs.hasSRGBMode == true
                            ? "Matches the monitor's Standard mode (full native gamut). Switch the monitor out of sRGB mode at the same time (see Monitor menu)."
                            : "The display's own profile describes its native colours.",
                        onByDefault: true))
                }
                if profile?.specs.hasSRGBMode == true,
                   ddcValues[VCP.colorPreset]?.current == ColorPreset.sRGB.rawValue {
                    changes.append(PlannedChange(
                        id: "ddc-preset",
                        change: .ddc(DDCTarget(vcp: VCP.colorPreset, value: .raw(ColorPreset.native.rawValue))),
                        title: "Monitor colour preset over DDC",
                        detail: "sRGB → Native (MCCS 0x14 = 0x02)",
                        why: "Undoes the sRGB preset set over DDC/CI. If the monitor's menu still shows sRGB afterwards, change it by hand.",
                        onByDefault: false,
                        isExperimental: true))
                }
                if isWideGamut && useCase.isGaming {
                    notes.append("In its native mode this panel shows more saturated colour than sRGB. Most games aren't colour-managed, so colours look punchier than intended. Many players like this; the editing presets make it accurate.")
                }
            }
        }

        // MARK: Brightness and contrast

        mutating func planBrightnessAndContrast() {
            if let brightness = ddcValues[VCP.brightness] {
                let peak = profile?.specs.peakSDRNits ?? RecommendationEngine.assumedPeakNits
                let target = useCase.isEditing ? context.lighting.editingNits(for: useCase) : context.lighting.comfortNits
                let percent = max(5, min(100, Int((target / peak * 100).rounded())))
                if abs(brightness.percent - percent) >= 2 {
                    let basis = profile?.specs.peakSDRNits != nil
                        ? "Estimated from the panel's rated \(Int(peak)) cd/m² peak"
                        : "Estimated assuming a typical \(Int(peak)) cd/m² panel"
                    let purpose = useCase.isEditing
                        ? "\(Int(target)) cd/m² is the usual editing target for a \(context.lighting.title.lowercased()) room. Too bright a screen makes you edit too dark, and prints come out dim."
                        : "About \(Int(target)) cd/m² is comfortable in a \(context.lighting.title.lowercased()) room without making an IPS panel's blacks glow."
                    changes.append(PlannedChange(
                        id: "ddc-brightness",
                        change: .ddc(DDCTarget(vcp: VCP.brightness, value: .percent(percent))),
                        title: "Brightness",
                        detail: "\(brightness.percent)% → \(percent)%",
                        why: "\(purpose) \(basis). A colorimeter gives the exact figure.",
                        onByDefault: true))
                    if useCase.isEditing { _ = sources(["dxo-targets", "diyp-calibration"]) }
                }
            }

            if let contrast = ddcValues[VCP.contrast], let factory = profile?.specs.defaultContrast,
               contrast.percent != factory {
                changes.append(PlannedChange(
                    id: "ddc-contrast",
                    change: .ddc(DDCTarget(vcp: VCP.contrast, value: .percent(factory))),
                    title: "Contrast",
                    detail: "\(contrast.percent)% → \(factory)% (factory)",
                    why: "On an LCD, the factory contrast is the highest setting that doesn't clip highlights. Raising it loses near-white detail, and lowering it dulls the picture.",
                    onByDefault: true))
            }

            if case .unavailable = display.ddc, !display.isBuiltIn {
                notes.append("This screen doesn't answer DDC/CI, so brightness and contrast have to be set with its own buttons.")
            }
        }

        // MARK: Night Shift

        mutating func planNightShift() {
            guard useCase.isEditing, context.nightShiftEnabled == true else { return }
            changes.append(PlannedChange(
                id: "night-shift",
                change: .nightShift(enabled: false),
                title: "Night Shift",
                detail: "On → Off",
                why: "Night Shift warms the white point away from D65, which shifts every colour you judge. Restore turns it back on.",
                onByDefault: true,
                isGlobal: true))
        }

        // MARK: Monitor menu

        mutating func planMonitorMenu() {
            if let profile {
                for item in profile.osd where item.useCases.contains(useCase) {
                    step(.monitorMenu, item.setting, item.value, path: item.path, why: item.why, sources: item.sourceIDs)
                }
                return
            }
            guard !display.isBuiltIn else { return }
            // Not in the database: settings that hold for nearly every monitor.
            if useCase.isEditing {
                step(.monitorMenu, "Picture mode", "sRGB if it exists, otherwise Standard/User",
                     path: "Monitor menu → Picture / Color",
                     why: "An sRGB mode clamps a wide-gamut panel to the colours web and photo work assume.")
                step(.monitorMenu, "Colour temperature", "6500K / Warm / Normal",
                     path: "Monitor menu → Color → Color Temp",
                     why: "D65 is the white point of sRGB, Display P3 and Rec. 709.")
                step(.monitorMenu, "Gamma", "2.2",
                     path: "Monitor menu → Picture → Gamma",
                     why: "The sRGB and macOS standard.", sources: ["dxo-targets"])
            } else {
                step(.monitorMenu, "Overdrive / Response time", "The middle setting (often Normal)",
                     path: "Monitor menu → Gaming",
                     why: "The fastest overdrive setting usually adds overshoot (bright or dark halos behind moving objects).")
                step(.monitorMenu, "Adaptive-Sync / FreeSync", "On",
                     path: "Monitor menu → Gaming",
                     why: "Needed for macOS's Variable refresh rate.", sources: ["apple-vrr"])
            }
            step(.monitorMenu, "Dynamic contrast, Eco, auto-brightness", "Off",
                 path: "Monitor menu → Picture",
                 why: "They change brightness on their own, which hides shadow detail and can cause flicker.")
        }

        // MARK: HDR

        mutating func planHDR() {
            let hdrLabel = profile?.specs.hdr
            guard hdrLabel != nil || display.edrHeadroom > 1 else { return }
            let isHDR400 = hdrLabel?.contains("400") ?? false
            switch useCase {
            case .immersiveGaming:
                step(.systemSettings, "High Dynamic Range", isHDR400 ? "Off, except for HDR games and films" : "On for HDR games and films",
                     path: "System Settings → Displays → \(display.name) → High Dynamic Range",
                     why: isHDR400
                        ? "DisplayHDR 400 doesn't require local dimming, so HDR mostly raises brightness without deeper blacks, and the macOS desktop looks washed out with it on. Try it per game."
                        : "HDR content gains highlight detail and brightness.",
                     sources: isHDR400 ? ["rtings-hdr", "tftcentral-hdr400"] : ["rtings-hdr"])
            case .photoEditing, .videoEditing:
                step(.systemSettings, "High Dynamic Range", "Off",
                     path: "System Settings → Displays → \(display.name) → High Dynamic Range",
                     why: "For SDR (sRGB / Rec. 709) work. HDR mode changes how the whole desktop is tone-mapped.")
            default:
                break
            }
        }

        // MARK: Apps

        mutating func planApps() {
            switch useCase {
            case .photoEditing:
                step(.apps, "Export for the web", "sRGB",
                     path: "Photoshop / Lightroom / Photos → Export → Color space",
                     why: "Browsers and phones assume sRGB. What you see in sRGB mode is what viewers get.",
                     sources: ["dxo-targets"])
            case .videoEditing:
                step(.apps, "Viewer colour management", "On",
                     path: "DaVinci Resolve → Settings → General → Use Mac display color profiles for viewers; Final Cut Pro manages colour automatically",
                     why: "Lets the editor show Rec. 709 through the monitor's profile instead of raw values.")
                notes.append("Broadcast grading targets BT.1886 (about gamma 2.4) in a dim room, which Apple's own displays offer as a reference mode. The sRGB mode uses the sRGB curve, so shadows look slightly lighter than on a grading reference. Only a colorimeter calibration to BT.1886 closes that gap.")
                _ = sources(["apple-reference-modes"])
            default:
                break
            }
            if useCase.isEditing && context.switchboardInstalled && display.ddc.isAvailable {
                step(.apps, "Switchboard brightness", "Keep it above the monitor's own minimum",
                     path: "Switchboard → Brightness",
                     why: "Below the monitor's hardware minimum, Switchboard dims through the colour table, which bends gamma and colours.")
            }
        }

        mutating func result() -> Recommendation {
            if let profile {
                notes.append(contentsOf: profile.notes)
            }
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
