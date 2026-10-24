import AppKit
import SwiftUI
import TunerCore

/// What the sidebar can show: a display, or one of the library pages.
enum SidebarItem: Hashable {
    case display(UInt32)
    case section(StudioSection)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("appearance") private var appearance = "system"

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: {
                if model.section == .studio { return model.selectedID.map(SidebarItem.display) }
                return .section(model.section)
            },
            set: { item in
                switch item {
                case .display(let id)?:
                    model.selectedID = id
                    model.section = .studio
                case .section(let section)?:
                    model.section = section
                case nil:
                    break
                }
                model.notice = nil
            })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Displays") {
                    ForEach(model.displays) { display in
                        DisplayRow(display: display, useCase: model.useCase(for: display.id))
                            .tag(SidebarItem.display(display.id))
                    }
                }
                Section("Library") {
                    ForEach([StudioSection.presets, .patterns, .activity]) { section in
                        Label(section.rawValue, systemImage: section.symbol)
                            .badge(section == .presets ? model.savedPresets.count : 0)
                            .tag(SidebarItem.section(section))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
            .safeAreaInset(edge: .bottom) {
                if model.isDemo {
                    Label("Demo: simulated displays", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        } detail: {
            Group {
                if model.isDemo && ProcessInfo.processInfo.arguments.contains("--popover") {
                    // Screenshot preview of the menu-bar panel.
                    MenuBarView()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LinearGradient(colors: [.indigo.opacity(0.6), .teal.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                switch model.section {
                case .studio:
                    if let display = model.selectedDisplay, !display.isSupported {
                        ContentUnavailableView("Not Supported", systemImage: "display.trianglebadge.exclamationmark",
                                               description: Text("Gamut Pro is built for the Acer Nitro XV272K V5 and leaves \(display.name) alone."))
                    } else if let display = model.selectedDisplay {
                        DisplayDetailView(display: display)
                    } else {
                        ContentUnavailableView("No Display Selected", systemImage: "display",
                                               description: Text("Connect a display, then choose Rescan."))
                    }
                case .presets: SavedPresetsView()
                case .patterns: PatternLibraryView()
                case .activity: ActivityView()
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.refresh(rescan: true) } label: { Label("Rescan Displays", systemImage: "arrow.clockwise") }
                    .help("Rescan displays and refresh monitor readings (⌘R)")
                    .disabled(model.isBusy || model.confirmation != nil || model.isDemo)
            }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(item: $model.confirmation) { confirmation in
            ConfirmView(deadline: confirmation.deadline).interactiveDismissDisabled()
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                    Text(notice).font(.callout)
                    Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.bottom, 80)
            }
        }
    }
}

struct DisplayRow: View {
    let display: DisplayFacts
    let useCase: UseCase

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } icon: {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : display.mirrorOf != nil ? "rectangle.on.rectangle" : "display")
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if !display.isSupported { return "Not supported" }
        if display.mirrorOf != nil { return "Mirroring" }
        let mode = display.currentMode?.refreshLabel ?? "Connected"
        return "\(useCase.title) · \(mode)"
    }
}

struct AppMark: View {
    var body: some View {
        if let image = NSImage(named: "AppIcon") {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "display").resizable().scaledToFit().foregroundStyle(.tint)
        }
    }
}

/// "Keep these display settings?" after a resolution or refresh change.
struct ConfirmView: View {
    @EnvironmentObject private var model: AppModel
    let deadline: Date

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "display").font(.system(size: 38)).foregroundStyle(.tint)
            Text("Keep these display settings?").font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                Text("Reverting in \(remaining) second\(remaining == 1 ? "" : "s").")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 10) {
                Button("Revert") { Task { await model.revertUnconfirmed() } }
                    .keyboardShortcut(.cancelAction)
                Button("Keep Settings") { model.keepChanges() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 360)
    }
}

extension DisplayFacts {
    /// Gamut Pro only changes the Acer Nitro XV272K V5.
    var isSupported: Bool { KnowledgeBase.match(name: name, vendorID: vendorID) != nil }
}
