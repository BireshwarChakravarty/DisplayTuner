import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TunerCore

enum StudioSection: String, CaseIterable, Identifiable {
    case studio = "Display Studio", presets = "Saved Presets", patterns = "Test Patterns", activity = "Activity"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .studio: return "display.2"; case .presets: return "square.stack.3d.up"; case .patterns: return "circle.lefthalf.filled"; case .activity: return "clock.arrow.circlepath" }
    }
}

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct StudioPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var useCase: UseCase
    var lighting: RoomLighting
    var displayKey: String
    var displayName: String
    var mode: DisplayMode?
    var brightness: Double?
    var contrast: Double?
    var date = Date()
    static func load() -> [Self] {
        guard let data = UserDefaults.standard.data(forKey: "studioPresets") else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
}

struct ActivityEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var detail: String
    var ok: Bool
    static func load() -> [Self] {
        guard let data = UserDefaults.standard.data(forKey: "studioActivity") else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
}

extension AppModel {
    func record(_ results: [ApplyResult]) {
        guard !isDemo else { return }
        let entries = results.map { ActivityEntry(title: $0.title, detail: "\($0.display) · \($0.message)", ok: $0.ok) }
        activity.insert(contentsOf: entries, at: 0)
        activity = Array(activity.prefix(100))
        UserDefaults.standard.set(try? JSONEncoder().encode(activity), forKey: "studioActivity")
    }

    func savePreset(name: String, display: DisplayFacts) {
        guard !isDemo else { notice = "Demo mode doesn’t save presets."; return }
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !cleaned.isEmpty else { return }
        savedPresets.insert(StudioPreset(name: cleaned, useCase: useCase(for: display.id), lighting: lighting,
            displayKey: display.key, displayName: display.name, mode: pickerMode(for: display),
            brightness: manualBrightness[display.id] ?? display.ddc.values[VCP.brightness].map { Double($0.percent) },
            contrast: manualContrast[display.id] ?? display.ddc.values[VCP.contrast].map { Double($0.percent) }), at: 0)
        persistPresets()
        notice = "Saved \(cleaned). Find it in Saved Presets."
    }

    func deletePreset(_ id: UUID) {
        savedPresets.removeAll { $0.id == id }
        persistPresets()
    }

    private func persistPresets() {
        UserDefaults.standard.set(try? JSONEncoder().encode(savedPresets), forKey: "studioPresets")
    }

    func loadPreset(_ preset: StudioPreset) {
        guard !isBusy && confirmation == nil else { return }
        guard let display = displays.first(where: { $0.key == preset.displayKey }) else {
            notice = "Connect \(preset.displayName) to use this preset."; return
        }
        selectedID = display.id
        setUseCase(preset.useCase, for: display.id)
        lighting = preset.lighting
        if let mode = preset.mode, display.modes.contains(where: { $0.matches(mode) }) { chooseMode(mode, for: display) }
        if !display.hasCalibration {
            manualBrightness[display.id] = preset.brightness
            manualContrast[display.id] = preset.contrast
        }
        section = .studio
        notice = "\(preset.name) loaded. Review your changes, then Apply."
    }

    func exportDiagnostics() {
        let report = """
        Display Tuner 2.0.0 — Diagnostics
        Generated: \(Date().formatted())
        System: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Mode: \(isDemo ? "Demo (simulated displays)" : "Live hardware")
        Night Shift: \(nightShiftEnabled.map { $0 ? "On" : "Off" } ?? "Unknown")

        """ + displays.map { d in
            """
            \(d.name)
            Built-in: \(d.isBuiltIn) | Mirrored: \(d.mirrorOf != nil)
            Mode: \(d.currentMode?.label ?? "Unknown")
            Calibration protected: \(d.hasCalibration)
            DDC: \(d.ddc.values.keys.sorted().map { v in "\(VCP.name(v)): \(d.ddc.values[v]!.current)/\(d.ddc.values[v]!.max)" }.joined(separator: ", "))
            Modes available: \(d.modes.count)
            Recommendations: \(recommendation(for: d).changes.map(\.title).joined(separator: ", "))

            """
        }.joined()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "DisplayTuner-Diagnostics.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try report.write(to: url, atomically: true, encoding: .utf8); notice = "Diagnostics exported." }
        catch { notice = error.localizedDescription }
    }

    func identify(_ display: DisplayFacts) {
        guard !isDemo, let screen = DisplayDetector.screen(for: display.id) else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: VStack(spacing: 8) {
            Image(systemName: "display").font(.system(size: 30))
            Text(display.name).font(.title2.bold())
            Text("Display Tuner").font(.caption).foregroundStyle(.secondary)
        }.frame(width: 360, height: 150).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)))
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 180, y: screen.frame.midY - 75))
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { panel.close() }
    }
}

enum DemoDisplays {
    static func make() -> [DisplayFacts] {
        var modes: [DisplayMode] = []
        for hz in [60.0, 120, 144, 160] {
            modes.append(DisplayMode(modeID: Int32(hz), width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: hz))
            modes.append(DisplayMode(modeID: Int32(hz + 500), width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: hz))
            modes.append(DisplayMode(modeID: Int32(hz + 1000), width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: hz))
        }
        modes.append(DisplayMode(modeID: 2000, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 320))
        return [DisplayFacts(id: 8001, name: "Acer Nitro XV272K V5", vendorID: 0x0472, productID: 1, serial: 1,
            modes: modes, currentMode: modes[0], widthMM: 597, primaries: .displayP3, profileName: "XV272K V5", edrHeadroom: 1.6,
            ddc: .available([VCP.brightness: VCPValue(current: 65, max: 100), VCP.contrast: VCPValue(current: 50, max: 100), VCP.colorPreset: VCPValue(current: 2, max: 11)])),
            DisplayFacts(id: 8002, name: "ARZOPA Portable", vendorID: 2, productID: 2, serial: 2, mirrorOf: 8001,
                modes: [DisplayMode(modeID: 1, width: 2560, height: 1600, pixelWidth: 2560, pixelHeight: 1600, refreshRate: 60)],
                currentMode: DisplayMode(modeID: 1, width: 2560, height: 1600, pixelWidth: 2560, pixelHeight: 1600, refreshRate: 60),
                primaries: .sRGB, profileName: "ARZOPA", ddc: .unavailable)]
    }
}
