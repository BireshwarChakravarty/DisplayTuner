import AppKit
import SwiftUI
import TunerCore

struct ApplyResult: Identifiable, Hashable {
    let id = UUID()
    let display: String
    let title: String
    let ok: Bool
    let message: String
}

/// "Keep these display settings?", shown after a resolution or refresh change.
struct Confirmation: Identifiable {
    let id = UUID()
    let deadline: Date
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [DisplayFacts] = []
    @Published var selectedID: UInt32?
    @Published var lighting: RoomLighting {
        didSet { if !isDemo { UserDefaults.standard.set(lighting.rawValue, forKey: "lighting") } }
    }
    @Published private(set) var useCases: [UInt32: UseCase] = [:]
    @Published private var toggles: [String: Bool] = [:]
    @Published private var modeChoices: [UInt32: DisplayMode] = [:]
    @Published private(set) var nightShiftEnabled: Bool?
    @Published private(set) var results: [ApplyResult] = []
    @Published var confirmation: Confirmation?
    @Published private(set) var isBusy = false
    @Published private(set) var lastSnapshot: Snapshot?
    @Published private(set) var originalSnapshot: Snapshot?
    @Published var manualBrightness: [UInt32: Double] = [:]
    @Published var manualContrast: [UInt32: Double] = [:]
    @Published var savedPresets: [StudioPreset] = StudioPreset.load()
    @Published var activity: [ActivityEntry] = ActivityEntry.load()
    @Published var notice: String?
    @Published var section: StudioSection = .studio
    let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
    private var pendingSnapshot: Snapshot?
    @Published private(set) var recoveryRequired = false
    private var probeGeneration = 0
    var canChange: Bool { !isBusy && confirmation == nil && !isDemo && !recoveryRequired }

    static let confirmSeconds = 15

    let switchboardInstalled = FileManager.default.fileExists(atPath: "/Applications/Switchboard.app")
    private let ddc = Arm64DDC()
    private let ddcQueue = DispatchQueue(label: "app.displaytuner.ddc")
    private let nightShift = NightShift()
    /// DDC state per monitor (by DisplayFacts.key), so it survives refreshes.
    private var ddcStatus: [String: DDCStatus] = [:]
    /// What each monitor reported it supports (by DisplayFacts.key).
    private var capabilityCache: [String: MonitorCapabilities] = [:]
    /// Automatic presets: what's applied because of the app in front, and the
    /// presets the person had chosen before, to return to.
    @Published var autoState: AutoState?
    var autoBaseline: [UInt32: UseCase] = [:]
    var autoObserver: NSObjectProtocol?
    var autoTask: Task<Void, Never>?
    var hintPanels: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var confirmTask: Task<Void, Never>?
    /// Live brightness from the menu bar: the latest value asked for per
    /// display, and which displays have a write in flight.
    private var liveTarget: [UInt32: UInt16] = [:]
    private var liveWriting: Set<UInt32> = []
    /// Modes applied for this session only, made permanent when kept.
    private var sessionModes: [UInt32: DisplayMode] = [:]
    /// DDC/CI pauses while displays sleep and for a few seconds after they
    /// wake: MonitorControl does the same because "some displays take time to
    /// recover".
    private var displaysAsleep = false
    private var ddcPausedUntil = Date.distantPast
    private var sleepObservers: [NSObjectProtocol] = []
    var ddcPaused: Bool { displaysAsleep || Date() < ddcPausedUntil }

    init() {
        lighting = RoomLighting(rawValue: UserDefaults.standard.string(forKey: "lighting") ?? "") ?? .normal
        lastSnapshot = SnapshotStore.load(.last)
        originalSnapshot = SnapshotStore.load(.original)
        if isDemo {
            displays = DemoDisplays.make()
            selectedID = displays.first?.id
            nightShiftEnabled = false
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--patterns") { section = .patterns }
            if arguments.contains("--presets") { section = .presets }
            if arguments.contains("--activity") { section = .activity }
            // "--usecase=photoEditing" (one argument: a bare word would be
            // taken by macOS as a file to open, and then no window opens).
            if let argument = arguments.first(where: { $0.hasPrefix("--usecase=") }),
               let useCase = UseCase(rawValue: String(argument.dropFirst("--usecase=".count))) {
                for display in displays { useCases[display.id] = useCase }
            }
            return
        }
        refresh()
        startAutoSwitching()
        if let recovery = SnapshotStore.load(.pending) {
            pendingSnapshot = recovery
            recoveryRequired = true
            Task { [weak self] in
                guard let self else { return }
                await self.restore(recovery)
                self.notice = self.recoveryRequired
                    ? "Recovery needs attention. Reconnect missing displays, then choose Retry recovery."
                    : "Recovered settings from an interrupted display change."
            }
        }
        watchSleep()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Detection

    var selectedDisplay: DisplayFacts? { displays.first { $0.id == selectedID } }

    func refresh(rescan: Bool = false) {
        guard !isDemo else { return }
        let topologyChanged = Set(DisplayDetector.onlineDisplayIDs()) != Set(displays.map(\.id))
        if rescan || topologyChanged {
            probeGeneration += 1
            ddcStatus.removeAll()
            capabilityCache.removeAll()
            let ddc = self.ddc
            ddcQueue.async { ddc.invalidate() }
        }
        let ddc = self.ddc
        var found = DisplayDetector.detect { id in ddc.productName(for: id) }
        for index in found.indices where !found[index].isBuiltIn {
            found[index].ddc = found[index].mirrorOf != nil || !found[index].isSupported ? .unavailable : (ddcStatus[found[index].key] ?? .unknown)
            found[index].capabilities = capabilityCache[found[index].key]
        }
        displays = found
        nightShiftEnabled = nightShift.isEnabled()
        if selectedID == nil || !found.contains(where: { $0.id == selectedID }) {
            selectedID = (found.first { !$0.isBuiltIn && $0.mirrorOf == nil } ?? found.first)?.id
        }
        probeDDC()
    }

    /// Read brightness, contrast and colour preset from each external monitor,
    /// once, in the background.
    private func probeDDC() {
        guard !ddcPaused else { return } // the wake handler probes again
        // Only the Acer is ever talked to over DDC/CI; other screens are left alone.
        for display in displays where display.isSupported && display.mirrorOf == nil && ddcStatus[display.key] == nil {
            let key = display.key
            ddcStatus[key] = .probing
            update(key) { $0.ddc = .probing }
            let identity = DisplayIdentity(id: display.id, name: display.name)
            let ddc = self.ddc
            let generation = probeGeneration
            ddcQueue.async { [weak self] in
                var values: [UInt8: VCPValue] = [:]
                for vcp in [VCP.brightness, VCP.contrast, VCP.colorPreset] {
                    if let value = ddc.read(vcp, for: identity) { values[vcp] = value }
                }
                let status: DDCStatus = values.isEmpty ? .unavailable : .available(values)
                Task { @MainActor [weak self] in
                    guard let self, self.probeGeneration == generation,
                          self.displays.contains(where: { $0.key == key }) else { return }
                    self.ddcStatus[key] = status
                    self.update(key) { $0.ddc = status }
                }
                // Then ask what it supports (slower: a few hundred bytes over DDC).
                guard !values.isEmpty, let text = ddc.capabilities(for: identity),
                      let capabilities = MonitorCapabilities.parse(text) else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.probeGeneration == generation,
                          self.displays.contains(where: { $0.key == key }) else { return }
                    self.capabilityCache[key] = capabilities
                    self.update(key) { $0.capabilities = capabilities }
                }
            }
        }
    }

    private func update(_ key: String, _ change: (inout DisplayFacts) -> Void) {
        for index in displays.indices where displays[index].key == key { change(&displays[index]) }
    }

    private func onDDCQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            ddcQueue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Recommendations

    var context: EngineContext {
        EngineContext(lighting: lighting, allDisplays: displays, nightShiftEnabled: nightShiftEnabled,
                      switchboardInstalled: switchboardInstalled)
    }

    func useCase(for id: UInt32) -> UseCase { useCases[id] ?? .everyday }

    func setUseCase(_ useCase: UseCase, for id: UInt32) {
        guard !isBusy && confirmation == nil else { return }
        manualBrightness[id] = nil
        manualContrast[id] = nil
        useCases[id] = useCase
        toggles = toggles.filter { !$0.key.hasPrefix("\(id)|") }
        modeChoices[id] = nil
    }

    func recommendation(for display: DisplayFacts) -> Recommendation {
        RecommendationEngine.recommend(useCase(for: display.id), for: display, context: context)
    }

    /// The recommendation's changes, with the mode the person picked (if any).
    func changes(for display: DisplayFacts) -> [PlannedChange] {
        var changes = recommendation(for: display).changes
        if !display.hasCalibration {
            for (vcp, values) in [(VCP.brightness, manualBrightness), (VCP.contrast, manualContrast)] {
                if let value = values[display.id], let current = display.ddc.values[vcp] {
                    let changeID = vcp == VCP.brightness ? "ddc-brightness" : "ddc-contrast"
                    changes.removeAll { $0.id == changeID }
                    guard abs(Double(current.percent) - value) >= 1 else { continue }
                    changes.append(PlannedChange(id: changeID, change: .ddc(DDCTarget(vcp: vcp, value: .percent(Int(value)))),
                        title: VCP.name(vcp), detail: "\(current.percent)% → \(Int(value))%", why: "Your manual adjustment.", onByDefault: true))
                }
            }
        }
        if let chosen = modeChoices[display.id] {
            changes.removeAll { $0.id == "mode" }
            if !(display.currentMode?.matches(chosen) ?? false) {
                changes.insert(PlannedChange(
                    id: "mode", change: .mode(chosen), title: "Resolution & refresh rate",
                    detail: "\(display.currentMode?.label ?? "Unknown") → \(chosen.label)",
                    why: "Chosen by you.", onByDefault: true), at: 0)
            }
        }
        return changes
    }

    /// The mode the picker shows: chosen, else recommended, else current.
    func pickerMode(for display: DisplayFacts) -> DisplayMode? {
        if let chosen = modeChoices[display.id] { return chosen }
        for change in recommendation(for: display).changes {
            if case .mode(let mode) = change.change { return mode }
        }
        return display.currentMode
    }

    func chooseMode(_ mode: DisplayMode, for display: DisplayFacts) {
        modeChoices[display.id] = mode
        toggles["\(display.id)|mode"] = true
    }

    func isOn(_ change: PlannedChange, for display: DisplayFacts) -> Bool {
        toggles["\(display.id)|\(change.id)"] ?? change.onByDefault
    }

    func setOn(_ on: Bool, _ change: PlannedChange, for display: DisplayFacts) {
        toggles["\(display.id)|\(change.id)"] = on
    }

    // MARK: Applying

    /// One preset on every external screen (from the menu bar).
    @discardableResult
    func quickApply(_ useCase: UseCase) async -> [ApplyResult] {
        guard canChange || isDemo else { return [] }
        let targets = displays.filter { $0.isSupported }
        if isDemo {
            for display in targets { useCases[display.id] = useCase }
            return []
        }
        for display in targets { setUseCase(useCase, for: display.id) }
        let applied = await apply(to: targets.map(\.id))
        showMonitorMenuHints(after: applied, on: targets)
        return applied
    }

    // MARK: Live controls (menu bar)

    /// Whether the menu-bar slider can move this monitor's backlight.
    func canSetBrightnessLive(_ display: DisplayFacts) -> Bool {
        !isBusy && confirmation == nil && !recoveryRequired && !ddcPaused && display.isSupported && display.mirrorOf == nil
            && !display.hasCalibration && display.ddc.values[VCP.brightness] != nil
    }

    /// Move a monitor's backlight while a slider drags. One write is in
    /// flight per display; only the latest value is sent after it.
    func setBrightnessLive(_ percent: Double, for display: DisplayFacts) {
        guard canSetBrightnessLive(display), let current = display.ddc.values[VCP.brightness] else { return }
        let raw = UInt16((min(max(percent, 0), 100) / 100 * Double(current.max)).rounded())
        guard raw != current.current else { return }
        var values = display.ddc.values
        values[VCP.brightness] = VCPValue(current: raw, max: current.max)
        if !isDemo { ddcStatus[display.key] = .available(values) }
        update(display.key) { $0.ddc = .available(values) }
        manualBrightness[display.id] = nil
        guard !isDemo else { return }
        liveTarget[display.id] = raw
        guard !liveWriting.contains(display.id) else { return }
        liveWriting.insert(display.id)
        pumpLive(DisplayIdentity(id: display.id, name: display.name))
    }

    private func pumpLive(_ identity: DisplayIdentity) {
        guard let raw = liveTarget.removeValue(forKey: identity.id) else {
            liveWriting.remove(identity.id)
            return
        }
        let ddc = self.ddc
        ddcQueue.async { [weak self] in
            _ = ddc.write(VCP.brightness, value: raw, for: identity)
            usleep(100_000) // at most about ten writes a second while dragging
            Task { @MainActor [weak self] in self?.pumpLive(identity) }
        }
    }

    func setNightShiftNow(_ on: Bool) {
        guard !isBusy, confirmation == nil else { return }
        if isDemo { nightShiftEnabled = on; return }
        nightShift.setEnabled(on)
        nightShiftEnabled = nightShift.isEnabled()
    }

    /// Apply each display's selected changes. `automatic` (app-based
    /// switching) never changes resolution or refresh rate, so it never needs
    /// the keep-or-revert countdown.
    @discardableResult
    func apply(to ids: [UInt32], automatic: Bool = false) async -> [ApplyResult] {
        guard canChange else { return [] }
        if ddcPaused {
            if !automatic {
                results = [ApplyResult(display: "", title: "Waiting for the display", ok: false,
                                       message: "The display is asleep or has just woken. Nothing was changed; try again in a few seconds.")]
            }
            return []
        }
        isBusy = true
        defer { isBusy = false }
        if !automatic { endAutoSwitch() } // the person's own choice wins

        refresh() // capture current modes, profiles and Night Shift before planning
        let plan: [(DisplayFacts, [PlannedChange])] = ids.compactMap { id in
            guard let display = displays.first(where: { $0.id == id }) else { return nil }
            let selected = changes(for: display).filter { change in
                guard isOn(change, for: display) else { return false }
                if automatic, case .mode = change.change { return false }
                return true
            }
            return selected.isEmpty ? nil : (display, selected)
        }
        guard !plan.isEmpty else {
            if !automatic {
                results = [ApplyResult(display: "", title: "Nothing to change", ok: true,
                                       message: "These settings are already in place. Do the monitor-menu steps below.")]
            }
            return []
        }

        // Abort before any write if rollback cannot be read and persisted.
        let snapshot: Snapshot
        do {
            snapshot = try await takeSnapshot(of: plan)
            let original = originalSnapshot?.keepingOriginals(addingFrom: snapshot) ?? snapshot
            try SnapshotStore.save(original, as: .original)
            try SnapshotStore.save(snapshot, as: .last)
            try SnapshotStore.save(snapshot, as: .pending)
            originalSnapshot = original
            lastSnapshot = snapshot
            pendingSnapshot = snapshot
        } catch {
            results = [ApplyResult(display: "", title: "Changes stopped safely", ok: false, message: error.localizedDescription)]
            return results
        }

        var newResults: [ApplyResult] = []
        var changedMode = false
        var didNightShift = false
        for (display, changes) in plan {
            let ordered = changes.sorted { a, b in
                func rank(_ c: PlannedChange) -> Int {
                    switch c.change {
                    case .mode: return 0
                    case .ddc(let target): return target.vcp == VCP.colorPreset ? 1 : 3
                    case .colorProfile: return 2
                    case .nightShift: return 4
                    }
                }
                return rank(a) < rank(b)
            }
            for change in ordered {
                if case .nightShift = change.change {
                    if didNightShift { continue }
                    didNightShift = true
                }
                let result = await perform(change, on: display)
                newResults.append(result)
                if case .mode = change.change, result.ok { changedMode = true }
            }
            modeChoices[display.id] = nil
            manualBrightness[display.id] = nil
            manualContrast[display.id] = nil
        }
        results = newResults
        Log.apply.info("Applied \(newResults.filter(\.ok).count) of \(newResults.count) changes")

        // ColorSync and the window server update shortly after.
        try? await Task.sleep(nanoseconds: 600_000_000)
        refresh()
        record(newResults, automatic: automatic)
        if changedMode { startConfirmation() }
        else { pendingSnapshot = nil; SnapshotStore.remove(.pending) }
        return newResults
    }

    private func takeSnapshot(of plan: [(DisplayFacts, [PlannedChange])]) async throws -> Snapshot {
        var entries: [DisplaySnapshot] = []
        for (display, changes) in plan {
            let vcps: [UInt8] = changes.compactMap {
                if case .ddc(let target) = $0.change { return target.vcp }
                return nil
            }
            var values: [UInt8: UInt16] = [:]
            if !vcps.isEmpty {
                let identity = DisplayIdentity(id: display.id, name: display.name)
                let ddc = self.ddc
                values = await onDDCQueue {
                    var read: [UInt8: UInt16] = [:]
                    for vcp in vcps { if let value = ddc.read(vcp, for: identity) { read[vcp] = value.current } }
                    return read
                }
            }
            guard vcps.allSatisfy({ values[$0] != nil }) else {
                throw StudioError.message("Couldn’t read the original monitor settings. No changes were made. Rescan and try again.")
            }
            let capturesMode = changes.contains { if case .mode = $0.change { return true }; return false }
            let capturesProfile = changes.contains { if case .colorProfile = $0.change { return true }; return false }
            if capturesMode && display.currentMode == nil { throw StudioError.message("Current display mode could not be saved.") }
            entries.append(DisplaySnapshot(
                key: display.key, name: display.name,
                mode: capturesMode && display.mirrorOf == nil ? display.currentMode : nil,
                hadCustomProfile: display.customProfilePath != nil,
                customProfilePath: display.customProfilePath,
                ddc: values, capturesProfile: capturesProfile))
        }
        let capturesNightShift = plan.contains { $0.1.contains { if case .nightShift = $0.change { return true }; return false } }
        let originalNightShift = capturesNightShift ? nightShift.isEnabled() : nil
        if capturesNightShift && originalNightShift == nil { throw StudioError.message("Night Shift could not be saved for undo.") }
        return Snapshot(displays: entries, nightShiftEnabled: originalNightShift)
    }

    private func perform(_ planned: PlannedChange, on display: DisplayFacts) async -> ApplyResult {
        func result(_ ok: Bool, _ message: String) -> ApplyResult {
            ApplyResult(display: display.name, title: planned.title, ok: ok, message: message)
        }

        switch planned.change {
        case .mode(let mode):
            // For this session only until Keep: a crash or restart during the
            // countdown can't leave an unconfirmed mode behind.
            let ok = DisplayModes.apply(mode, to: display.id, permanent: false)
            if ok { sessionModes[display.id] = mode }
            return result(ok, ok ? "Now \(mode.label)." : "macOS didn't accept \(mode.label).")

        case .colorProfile(let choice):
            let url = ColorProfiles.url(for: choice)
            if case .system(let file) = choice, url == nil {
                return result(false, "\(file) isn't in /System/Library/ColorSync/Profiles on this Mac.")
            }
            let ok = ColorProfiles.setProfile(url, for: display.id)
            return result(ok, ok ? "Now using \(choice.label)." : "ColorSync didn't accept the change.")

        case .ddc(let target):
            // Only the controls Acer documents in the Picture menu. The manual
            // warns that "improper adjustment of other controls may result in
            // damage", and it documents no DDC/CI colour presets.
            guard target.vcp == VCP.brightness || target.vcp == VCP.contrast else {
                return result(false, "Display Tuner only changes brightness and contrast over DDC/CI.")
            }
            guard let current = display.ddc.values[target.vcp] else {
                return result(false, "The monitor didn't report this control over DDC/CI.")
            }
            let raw = target.rawValue(max: current.max)
            let identity = DisplayIdentity(id: display.id, name: display.name)
            let ddc = self.ddc
            let (sent, readBack) = await onDDCQueue { () -> (Bool, VCPValue?) in
                let sent = ddc.write(target.vcp, value: raw, for: identity)
                usleep(150_000) // let the monitor settle before asking
                return (sent, sent ? ddc.read(target.vcp, for: identity) : nil)
            }
            if let readBack {
                var values = ddcStatus[display.key]?.values ?? display.ddc.values
                values[target.vcp] = readBack
                ddcStatus[display.key] = .available(values)
            }
            let name = VCP.name(target.vcp)
            let shown: (UInt16) -> String = { value in
                if case .percent = target.value { return "\(VCPValue(current: value, max: current.max).percent)%" }
                return String(format: "0x%02X", value)
            }
            if !sent { return result(false, "The monitor didn't respond over DDC/CI.") }
            guard let readBack else { return result(false, "Unverified: \(name) sent as \(shown(raw)); the monitor didn't report it back.") }
            if readBack.current == raw { return result(true, "\(name) is now \(shown(raw)).") }
            return result(false, "The monitor kept \(name.lowercased()) at \(shown(readBack.current)). It probably locks this setting in its current picture mode (sRGB modes often do). Set it in the monitor's menu.")

        case .nightShift(let enabled):
            let accepted = nightShift.setEnabled(enabled)
            nightShiftEnabled = nightShift.isEnabled()
            let ok = accepted && nightShiftEnabled == enabled
            return ApplyResult(display: "All screens", title: "Night Shift", ok: ok,
                               message: ok ? "Night Shift is \(enabled ? "on" : "off")." : "Couldn't change Night Shift on this Mac. Turn it off in System Settings → Displays → Night Shift.")
        }
    }

    // MARK: Confirm or revert

    private func startConfirmation() {
        confirmTask?.cancel()
        confirmation = Confirmation(deadline: Date().addingTimeInterval(TimeInterval(Self.confirmSeconds)))
        NSApp.activate()
        confirmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.confirmSeconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.revertUnconfirmed()
        }
    }

    func keepChanges() {
        for (id, mode) in sessionModes where displays.contains(where: { $0.id == id }) {
            _ = DisplayModes.apply(mode, to: id, permanent: true)
        }
        sessionModes.removeAll()
        pendingSnapshot = nil
        SnapshotStore.remove(.pending)
        confirmTask?.cancel()
        confirmTask = nil
        confirmation = nil
    }

    func revertUnconfirmed() async {
        sessionModes.removeAll()
        confirmTask?.cancel()
        confirmTask = nil
        confirmation = nil
        if let snapshot = pendingSnapshot {
            recoveryRequired = true
            await restore(snapshot)
        }
    }

    // MARK: Restoring

    func undoLastApply() async {
        guard !isBusy && !isDemo else { return }
        if recoveryRequired, let pendingSnapshot { await restore(pendingSnapshot); return }
        guard canChange, let lastSnapshot else { return }
        await restore(lastSnapshot)
    }

    func restoreOriginals() async {
        guard canChange, let originalSnapshot else { return }
        await restore(originalSnapshot)
    }

    private func restore(_ snapshot: Snapshot) async {
        guard !isBusy && !isDemo else { return }
        isBusy = true
        refresh()
        defer { isBusy = false }

        var newResults: [ApplyResult] = []
        for saved in snapshot.displays where !displays.contains(where: { $0.key == saved.key }) {
            newResults.append(ApplyResult(display: saved.name, title: "Display disconnected", ok: false,
                message: "Reconnect this display and choose Undo to restore its settings."))
        }
        for display in displays {
            guard let saved = snapshot.display(display.key) else { continue }

            if display.mirrorOf == nil, let mode = saved.mode, !(display.currentMode?.matches(mode) ?? false) {
                let ok = DisplayModes.apply(mode, to: display.id)
                newResults.append(ApplyResult(display: display.name, title: "Resolution & refresh rate", ok: ok,
                                              message: ok ? "Back to \(mode.label)." : "Couldn't switch back to \(mode.label)."))
            }

            if saved.capturesProfile && saved.customProfilePath != display.customProfilePath {
                let url = saved.hadCustomProfile ? saved.customProfilePath.map { URL(fileURLWithPath: $0) } : nil
                let ok = ColorProfiles.setProfile(url, for: display.id)
                newResults.append(ApplyResult(display: display.name, title: "Colour profile", ok: ok,
                                              message: ok ? "Back to \(url?.deletingPathExtension().lastPathComponent ?? "the display's own profile")." : "ColorSync didn't accept the change."))
            }

            if !saved.ddc.isEmpty && display.mirrorOf == nil && ddcPaused {
                newResults.append(ApplyResult(display: display.name, title: "Monitor settings", ok: false,
                    message: "The display is asleep or has just woken. Try Undo again in a few seconds."))
            } else if !saved.ddc.isEmpty && display.mirrorOf == nil {
                let identity = DisplayIdentity(id: display.id, name: display.name)
                let ddc = self.ddc
                let values = saved.ddc
                let failed = await onDDCQueue { () -> [UInt8] in
                    let ordered = values.keys.sorted { a, b in
                        if a == b { return false }
                        if a == VCP.colorPreset { return true }
                        if b == VCP.colorPreset { return false }
                        return a < b
                    }
                    return ordered.compactMap { vcp in
                        guard let value = values[vcp], ddc.write(vcp, value: value, for: identity) else { return vcp }
                        usleep(150_000)
                        return ddc.read(vcp, for: identity)?.current == value ? nil : vcp
                    }
                }
                newResults.append(ApplyResult(
                    display: display.name, title: "Monitor settings", ok: failed.isEmpty,
                    message: failed.isEmpty
                        ? "Restored \(values.keys.sorted().map(VCP.name).joined(separator: ", ").lowercased())."
                        : "The monitor didn't take \(failed.map(VCP.name).joined(separator: ", ").lowercased())."))
                ddcStatus[display.key] = nil // read fresh values
            }
        }

        if let wanted = snapshot.nightShiftEnabled, wanted != nightShiftEnabled {
            let ok = nightShift.setEnabled(wanted) && nightShift.isEnabled() == wanted
            newResults.append(ApplyResult(display: "All screens", title: "Night Shift", ok: ok,
                                          message: ok ? "Night Shift is \(wanted ? "on" : "off") again." : "Couldn't change Night Shift."))
        }

        results = newResults.isEmpty
            ? [ApplyResult(display: "", title: "Nothing to restore", ok: true, message: "Everything already matches.")]
            : newResults
        try? await Task.sleep(nanoseconds: 600_000_000)
        refresh(rescan: true)
        record(newResults)
        if newResults.allSatisfy(\.ok) {
            SnapshotStore.remove(.pending)
            pendingSnapshot = nil
            recoveryRequired = false
        } else if pendingSnapshot != nil { recoveryRequired = true }
    }

    // MARK: Sleep and wake

    /// Pause DDC/CI while the screens or the Mac sleep, and for three seconds
    /// after they wake, then read the monitor afresh.
    private func watchSleep() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.displaysAsleep = true }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.displaysAsleep = false
                    self.ddcPausedUntil = Date().addingTimeInterval(3)
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    guard !self.displaysAsleep else { return }
                    self.refresh(rescan: true)
                }
            })
        }
    }
}

/// Snapshots on disk, in ~/Library/Application Support/DisplayTuner.
enum SnapshotStore {
    enum Name: String {
        /// Before the most recent apply.
        case last
        /// Before Display Tuner first changed each setting.
        case original
        case pending
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DisplayTuner", isDirectory: true)
    }

    static func load(_ name: Name) -> Snapshot? {
        let url = directory.appendingPathComponent("\(name.rawValue).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot, as name: Name) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent("\(name.rawValue).json"), options: .atomic)
    }

    static func remove(_ name: Name) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(name.rawValue).json"))
    }
}
