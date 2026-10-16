import AppKit
import SwiftUI

@main
struct DisplayTunerApp: App {
    @NSApplicationDelegateAdaptor(StudioLifecycle.self) private var lifecycle
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Display Tuner", id: "main") {
            ContentView()
                .environmentObject(model)
                .onAppear { lifecycle.model = model }
                .frame(minWidth: 1060, minHeight: 760)
                .background(WindowCaptureBridge())
        }
        .defaultSize(width: 1260, height: 940)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Displays") { model.refresh(rescan: true) }.keyboardShortcut("r").disabled(!model.canChange)
                Button("Export Diagnostics…") { model.exportDiagnostics() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Undo Last Apply") { Task { await model.undoLastApply() } }.keyboardShortcut("z").disabled(model.lastSnapshot == nil || !model.canChange)
            }
            CommandMenu("Workspace") {
                ForEach(Array(StudioSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { model.section = section }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
        }
        MenuBarExtra("Display Tuner", systemImage: "dial.medium") { MenuBarView().environmentObject(model) }
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
        if model.isBusy { NSSound.beep(); return .terminateCancel }
        guard model.confirmation != nil else { return .terminateNow }
        Task {
            await model.revertUnconfirmed()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
