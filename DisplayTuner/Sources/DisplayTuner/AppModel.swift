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
        didSet { UserDefaults.standard.set(lighting.rawValue, forKey: "lighting") }
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

    static let confirmSeconds = 15

    let switchboardInstalled = FileManager.default.fileExists(atPath: "/Applications/Switchboard.app")
    private let ddc = Arm64DDC()
    private let ddcQueue = DispatchQueue(label: "app.displaytuner.ddc")
    private let nightShift = NightShift()
    /// DDC state per monitor (by DisplayFacts.key), so it survives refreshes.
    private var ddcStatus: [String: DDCStatus] = [:]
    private var screenObserver: NSObjectProtocol?
    private var confirmTask: Task<Void, Never>?

    init() {
        lighting = RoomLighting(rawValue: UserDefaults.standard.string(forKey: "lighting") ?? "") ?? .normal
        lastSnapshot = SnapshotStore.load(.last)
        originalSnapshot = SnapshotStore.load(.original)
        refresh()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Detection

    var selectedDisplay: DisplayFacts? { displays.first { $0.id == selectedID } }

    func refresh() {
        let ddc = self.ddc
        var found = DisplayDetector.detect { id in ddc.productName(for: id) }
        for index in found.indices where !found[index].isBuiltIn {
            found[index].ddc = ddcStatus[found[index].key] ?? .unknown
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
        for display in displays where !display.isBuiltIn && ddcStatus[display.key] == nil {
            let key = display.key
            ddcStatus[key] = .probing
            update(key) { $0.ddc = .probing }
            let identity = DisplayIdentity(id: display.id, name: display.name)
            let ddc = self.ddc
            ddcQueue.async {
                var values: [UInt8: VCPValue] = [:]
                if let brightness = ddc.read(VCP.brightness, for: identity) {
                    values[VCP.brightness] = brightness
                    for vcp in [VCP.contrast, VCP.colorPreset] {
                        if let value = ddc.read(vcp, for: identity) { values[vcp] = value }
                    }
                }
                let status: DDCStatus = values.isEmpty ? .unavailable : .available(values)
                Task { @MainActor [weak self] in
                    self?.ddcStatus[key] = status
                    self?.update(key) { $0.ddc = status }
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
    func quickApply(_ useCase: UseCase) async {
        let targets = displays.filter { !$0.isBuiltIn }
        for display in targets { setUseCase(useCase, for: display.id) }
        await apply(to: targets.map(\.id))
    }

    func apply(to ids: [UInt32]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let plan: [(DisplayFacts, [PlannedChange])] = ids.compactMap { id in
            guard let display = displays.first(where: { $0.id == id }) else { return nil }
            let selected = changes(for: display).filter { isOn($0, for: display) }
            return selected.isEmpty ? nil : (display, selected)
        }
        guard !plan.isEmpty else {
            results = [ApplyResult(display: "", title: "Nothing to change", ok: true,
                                   message: "These settings are already in place. Do the monitor-menu steps below.")]
            return
        }

        // Save how things are now, so it can all be undone.
        let snapshot = await takeSnapshot(of: plan)
        lastSnapshot = snapshot
        SnapshotStore.save(snapshot, as: .last)
        let original = originalSnapshot?.keepingOriginals(addingFrom: snapshot) ?? snapshot
        originalSnapshot = original
        SnapshotStore.save(original, as: .original)

        var newResults: [ApplyResult] = []
        var changedMode = false
        var didNightShift = false
        for (display, changes) in plan {
            for change in changes {
                if case .nightShift = change.change {
                    if didNightShift { continue }
                    didNightShift = true
                }
                let result = await perform(change, on: display)
                newResults.append(result)
                if case .mode = change.change, result.ok { changedMode = true }
            }
            modeChoices[display.id] = nil
        }
        results = newResults
        Log.apply.info("Applied \(newResults.filter(\.ok).count) of \(newResults.count) changes")

        // ColorSync and the window server update shortly after.
        try? await Task.sleep(nanoseconds: 600_000_000)
        refresh()
        if changedMode { startConfirmation() }
    }

    private func takeSnapshot(of plan: [(DisplayFacts, [PlannedChange])]) async -> Snapshot {
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
            entries.append(DisplaySnapshot(
                key: display.key, name: display.name,
                mode: display.mirrorOf == nil ? display.currentMode : nil,
                hadCustomProfile: display.customProfilePath != nil,
                customProfilePath: display.customProfilePath,
                ddc: values))
        }
        return Snapshot(displays: entries, nightShiftEnabled: nightShiftEnabled)
    }

    private func perform(_ planned: PlannedChange, on display: DisplayFacts) async -> ApplyResult {
        func result(_ ok: Bool, _ message: String) -> ApplyResult {
            ApplyResult(display: display.name, title: planned.title, ok: ok, message: message)
        }

        switch planned.change {
        case .mode(let mode):
            let ok = DisplayModes.apply(mode, to: display.id)
            return result(ok, ok ? "Now \(mode.label)." : "macOS didn't accept \(mode.label).")

        case .colorProfile(let choice):
            let url = ColorProfiles.url(for: choice)
            if case .system(let file) = choice, url == nil {
                return result(false, "\(file) isn't in /System/Library/ColorSync/Profiles on this Mac.")
            }
            let ok = ColorProfiles.setProfile(url, for: display.id)
            return result(ok, ok ? "Now using \(choice.label)." : "ColorSync didn't accept the change.")

        case .ddc(let target):
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
            guard let readBack else { return result(true, "\(name) sent as \(shown(raw)); the monitor didn't report it back.") }
            if readBack.current == raw { return result(true, "\(name) is now \(shown(raw)).") }
            return result(false, "The monitor kept \(name.lowercased()) at \(shown(readBack.current)). It probably locks this setting in its current picture mode (sRGB modes often do). Set it in the monitor's menu.")

        case .nightShift(let enabled):
            let ok = nightShift.setEnabled(enabled)
            nightShiftEnabled = nightShift.isEnabled()
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
        confirmTask?.cancel()
        confirmTask = nil
        confirmation = nil
    }

    func revertUnconfirmed() async {
        confirmTask?.cancel()
        confirmTask = nil
        confirmation = nil
        if let lastSnapshot { await restore(lastSnapshot) }
    }

    // MARK: Restoring

    func undoLastApply() async {
        guard let lastSnapshot else { return }
        await restore(lastSnapshot)
    }

    func restoreOriginals() async {
        guard let originalSnapshot else { return }
        await restore(originalSnapshot)
    }

    private func restore(_ snapshot: Snapshot) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        var newResults: [ApplyResult] = []
        for display in displays {
            guard let saved = snapshot.display(display.key) else { continue }

            if display.mirrorOf == nil, let mode = saved.mode, !(display.currentMode?.matches(mode) ?? false) {
                let ok = DisplayModes.apply(mode, to: display.id)
                newResults.append(ApplyResult(display: display.name, title: "Resolution & refresh rate", ok: ok,
                                              message: ok ? "Back to \(mode.label)." : "Couldn't switch back to \(mode.label)."))
            }

            if saved.customProfilePath != display.customProfilePath {
                let url = saved.hadCustomProfile ? saved.customProfilePath.map { URL(fileURLWithPath: $0) } : nil
                let ok = ColorProfiles.setProfile(url, for: display.id)
                newResults.append(ApplyResult(display: display.name, title: "Colour profile", ok: ok,
                                              message: ok ? "Back to \(url?.deletingPathExtension().lastPathComponent ?? "the display's own profile")." : "ColorSync didn't accept the change."))
            }

            if !saved.ddc.isEmpty {
                let identity = DisplayIdentity(id: display.id, name: display.name)
                let ddc = self.ddc
                let values = saved.ddc
                let failed = await onDDCQueue { () -> [UInt8] in
                    values.compactMap { vcp, value in ddc.write(vcp, value: value, for: identity) ? nil : vcp }
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
            let ok = nightShift.setEnabled(wanted)
            newResults.append(ApplyResult(display: "All screens", title: "Night Shift", ok: ok,
                                          message: ok ? "Night Shift is \(wanted ? "on" : "off") again." : "Couldn't change Night Shift."))
        }

        results = newResults.isEmpty
            ? [ApplyResult(display: "", title: "Nothing to restore", ok: true, message: "Everything already matches.")]
            : newResults
        try? await Task.sleep(nanoseconds: 600_000_000)
        refresh()
    }
}

/// Snapshots on disk, in ~/Library/Application Support/DisplayTuner.
enum SnapshotStore {
    enum Name: String {
        /// Before the most recent apply.
        case last
        /// Before Display Tuner first changed each setting.
        case original
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

    static func save(_ snapshot: Snapshot, as name: Name) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: directory.appendingPathComponent("\(name.rawValue).json"), options: .atomic)
        } catch {
            Log.apply.error("Couldn't save snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}
