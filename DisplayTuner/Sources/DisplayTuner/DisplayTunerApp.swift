import AppKit
import SwiftUI

@main
struct DisplayTunerApp: App {
    @NSApplicationDelegateAdaptor(StudioLifecycle.self) private var lifecycle
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Gamut Pro", id: "main") {
            ContentView()
                .environmentObject(model)
                .onAppear { lifecycle.model = model }
                .frame(minWidth: 880, minHeight: 600)
                .background(WindowCaptureBridge())
        }
        .defaultSize(width: 1120, height: 860)
        .defaultLaunchBehavior(.presented) // always open the window at launch, even after an unclean quit
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Displays") { model.refresh(rescan: true) }.keyboardShortcut("r").disabled(!model.canChange)
                Button("Export Diagnostics…") { model.exportDiagnostics() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Undo Last Apply") { Task { await model.undoLastApply() } }.keyboardShortcut("z", modifiers: [.command, .option]).disabled(model.lastSnapshot == nil || !model.canChange)
            }
            CommandMenu("Workspace") {
                ForEach(Array(StudioSection.allCases.prefix(9).enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { model.section = section }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
        }
        MenuBarExtra("Gamut Pro", systemImage: "dial.medium") { MenuBarView().environmentObject(model) }
            .menuBarExtraStyle(.window)
        Settings { StudioSettingsView().environmentObject(model) }
    }
}

/// Optional app-window-only screenshot for release QA, never the desktop.
struct WindowCaptureBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--screenshot"), ProcessInfo.processInfo.arguments.count > index + 1 {
            let path = ProcessInfo.processInfo.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let content = view.window?.contentView,
                      let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
            }
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

@MainActor
final class StudioLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard model.isBusy || model.confirmation != nil || model.autoState != nil else { return .terminateNow }
        // Let a running change finish (briefly), revert an unconfirmed mode and
        // undo an automatic preset, without cancelling a logout or shutdown.
        Task {
            for _ in 0..<50 where model.isBusy { try? await Task.sleep(nanoseconds: 100_000_000) }
            if model.confirmation != nil { await model.revertUnconfirmed() }
            if model.autoState != nil { await model.leaveAutoSwitch() }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
