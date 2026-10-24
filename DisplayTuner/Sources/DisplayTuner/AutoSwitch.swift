import AppKit
import SwiftUI
import TunerCore

/// A preset applied because of the app in front.
struct AutoState: Equatable {
    var useCase: UseCase
    var appName: String
}

enum AutoSwitchSettings {
    static let enabledKey = "autoSwitch"
    static let gamePresetKey = "autoGamePreset"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var gamePreset: UseCase {
        UseCase(rawValue: UserDefaults.standard.string(forKey: gamePresetKey) ?? "") ?? .immersiveGaming
    }
}

extension AppModel {
    /// Watch which app is in front. Switching only happens while the setting is on.
    func startAutoSwitching() {
        guard !isDemo, autoObserver == nil else { return }
        autoObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.frontmostAppChanged(app) }
        }
    }

    func setAutoSwitch(enabled: Bool, gamePreset: UseCase) {
        guard !isDemo else { return }
        UserDefaults.standard.set(enabled, forKey: AutoSwitchSettings.enabledKey)
        UserDefaults.standard.set(gamePreset.rawValue, forKey: AutoSwitchSettings.gamePresetKey)
        if !enabled {
            // Turned off (usually from this app's own Settings): undo the automatic preset now.
            Task { await leaveAutoSwitch() }
        } else if let app = NSWorkspace.shared.frontmostApplication {
            frontmostAppChanged(app, delay: 0)
        }
    }

    /// Forget automatic state: the person chose something themselves.
    func endAutoSwitch() {
        autoTask?.cancel()
        autoTask = nil
        autoState = nil
        autoBaseline = [:]
        autoSnapshot = nil
    }

    private func frontmostAppChanged(_ app: NSRunningApplication?, delay: Double = 1.5) {
        // Ignore Gamut Pro itself and background UI (login window, screen saver, menu extras).
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else { return }
        autoTask?.cancel()
        autoTask = Task { [weak self] in
            // Wait until the person settles on an app: ⌘-Tab passes through others.
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.evaluateAutoSwitch(for: app)
        }
    }

    private func preset(for app: NSRunningApplication) -> UseCase? {
        guard AutoSwitchSettings.isEnabled else { return nil }
        let bundle = app.bundleURL.flatMap(Bundle.init(url:))
        return AppRules.useCase(
            bundleID: app.bundleIdentifier,
            category: bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
            path: app.bundleURL?.path,
            gamePreset: AutoSwitchSettings.gamePreset)
    }

    private func evaluateAutoSwitch(for app: NSRunningApplication) async {
        guard canChange else { return } // busy or confirming: the next app switch tries again
        let name = app.localizedName ?? "this app"
        if let wanted = preset(for: app) {
            if autoState?.useCase == wanted { autoState?.appName = name; return }
            let targets = displays.filter { $0.isSupported && $0.mirrorOf == nil }
            guard !targets.isEmpty else { return }
            if autoState == nil {
                autoBaseline = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, useCase(for: $0.id)) })
            }
            for display in targets { setUseCase(wanted, for: display.id) }
            let results = await apply(to: targets.map(\.id), automatic: true)
            autoState = AutoState(useCase: wanted, appName: name)
            showMonitorMenuHints(after: results, on: targets)
        } else {
            await leaveAutoSwitch()
        }
    }

    /// Back to exactly how things were before, Night Shift included, rather
    /// than re-applying the preset card that was selected.
    func leaveAutoSwitch() async {
        guard autoState != nil, canChange else { return }
        let baseline = autoBaseline
        let snapshot = autoSnapshot
        autoState = nil
        autoBaseline = [:]
        autoSnapshot = nil
        for (id, useCase) in baseline { setUseCase(useCase, for: id) }
        if let snapshot { await restoreAfterAuto(snapshot) }
    }

    /// The colour profile changed, and only the monitor's own menu can switch
    /// its Color Space to match: say so on that screen.
    func showMonitorMenuHints(after results: [ApplyResult], on targets: [DisplayFacts]) {
        for display in targets {
            let mine = results.filter { $0.display == display.name }
            guard mine.contains(where: { $0.title == "Colour profile" && $0.ok }),
                  let step = recommendation(for: display).manualSteps.first(where: { $0.place == .monitorMenu && $0.setting == "Color Space" })
            else { continue }
            showHint(on: display, title: "Set Color Space to \(step.value)", detail: step.path)
        }
    }

    /// A short floating card in the middle of a screen.
    func showHint(on display: DisplayFacts, title: String, detail: String, symbol: String = "slider.horizontal.3", seconds: Double = 6) {
        guard !isDemo, let screen = DisplayDetector.screen(for: display.id) else { return }
        let size = NSSize(width: 420, height: 150)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HintCard(title: title, detail: detail, symbol: symbol)
            .frame(width: size.width, height: size.height))
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        panel.orderFrontRegardless()
        hintPanels.append(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            panel.close()
            self?.hintPanels.removeAll { $0 === panel }
        }
    }
}

struct HintCard: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(.tint)
            Text(title).font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}
