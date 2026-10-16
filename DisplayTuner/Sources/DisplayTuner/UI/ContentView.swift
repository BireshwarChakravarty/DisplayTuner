import SwiftUI
import TunerCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @AppStorage("appearance") private var appearance = "dark"

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 230)
            Rectangle().fill(.primary.opacity(0.06)).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Group {
                    switch model.section {
                    case .studio:
                        if let display = model.selectedDisplay { DisplayDetailView(display: display) }
                        else { ContentUnavailableView("Your studio starts here", systemImage: "display.2", description: Text("Connect a display, then rescan to discover its capabilities.")) }
                    case .presets: SavedPresetsView()
                    case .patterns: PatternLibraryView()
                    case .activity: ActivityView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(StudioBackdrop())
        .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
        .tint(.studioCyan)
        .sheet(item: $model.confirmation) { confirmation in
            ConfirmView(deadline: confirmation.deadline).interactiveDismissDisabled()
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Color.studioCyan)
                    Text(notice).font(.callout)
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                }.padding(14).modifier(StudioGlass()).padding(.top, 54).padding(.horizontal, 30)
                .shadow(color: .black.opacity(0.18), radius: 20).zIndex(10)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark().frame(width: 35, height: 35)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Display Tuner").font(.system(size: 14, weight: .bold))
                    Text("YOUR DISPLAY, REFINED").font(.system(size: 7, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
                }
            }.padding(.top, 24).padding(.bottom, 28).padding(.horizontal, 20)
            Eyebrow(text: "Workspace").padding(.horizontal, 22).padding(.bottom, 10)
            ForEach(StudioSection.allCases) { section in
                Button {
                    model.section = section
                    model.notice = nil
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.symbol).font(.system(size: 14)).frame(width: 20)
                        Text(section.rawValue).font(.system(size: 12, weight: model.section == section ? .semibold : .medium))
                        Spacer()
                        if section == .presets, !model.savedPresets.isEmpty { Text("\(model.savedPresets.count)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .foregroundStyle(model.section == section ? Color.studioCyan : Color.primary.opacity(0.65))
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(model.section == section ? Color.studioCyan.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.horizontal, 10)
            }
            HStack { Eyebrow(text: "Connected displays"); Spacer(); Text("\(model.displays.count)").font(.caption2).foregroundStyle(.secondary) }
                .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.displays) { display in
                        Button {
                            model.selectedID = display.id
                            model.section = .studio
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display").font(.system(size: 20)).foregroundStyle(model.selectedID == display.id ? Color.studioCyan : .secondary).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(display.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                                    Text(display.mirrorOf != nil ? "Mirrored display" : display.currentMode?.refreshLabel ?? "Connected")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Circle().fill(Color.studioCyan).frame(width: 4, height: 4).padding(.top, 6)
                            }.padding(12)
                                .background(model.selectedID == display.id ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel("Select \(display.name)")
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 10) {
                Label(model.isDemo ? "DEMO WORKSPACE" : "ON-DEVICE & PRIVATE", systemImage: model.isDemo ? "sparkles" : "lock.shield")
                    .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Color.studioCyan)
                Text(model.isDemo ? "Simulated screens. Hardware controls are disabled." : "Your display settings stay on your Mac.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).background(Color.studioCyan.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)).padding(14)
            HStack {
                Text("VERSION \(AppVersion.current)").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary)
                Spacer()
                Button { openSettings() } label: { Image(systemName: "gearshape").font(.system(size: 13)) }.buttonStyle(.plain).help("Settings")
            }.padding(.horizontal, 22).padding(.bottom, 18)
        }.background(.ultraThinMaterial)
    }

    private var topbar: some View {
        HStack {
            Text("WORKSPACE").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary)
            Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(.tertiary)
            Text(model.section.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if model.isDemo { StatusPill(text: "DEMO", color: .orange) }
            else { StatusPill(text: "\(model.displays.count) DISPLAYS ONLINE") }
            Button { model.refresh(rescan: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12)) }
                .buttonStyle(.plain).padding(.leading, 12).help("Rescan displays and refresh hardware readings (⌘R)")
                .disabled(model.isBusy || model.confirmation != nil || model.isDemo)
        }.padding(.horizontal, 28).frame(height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.055)).frame(height: 1) }
    }
}

struct AppMark: View {
    var body: some View {
        if let image = NSImage(named: "AppIcon") { Image(nsImage: image).resizable().scaledToFit() }
        else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [.studioCyan, .studioViolet], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "display").font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
            }
        }
    }
}

struct ConfirmView: View {
    @EnvironmentObject private var model: AppModel
    let deadline: Date
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 36)).foregroundStyle(Color.studioCyan)
            Text("Everything looking good?").font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                Text("Your previous settings return in \(remaining) seconds.").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 12) {
                Button("Revert") { Task { await model.revertUnconfirmed() } }.keyboardShortcut(.cancelAction).buttonStyle(StudioButton())
                Button("Keep settings") { model.keepChanges() }.keyboardShortcut(.defaultAction).buttonStyle(StudioButton(prominent: true))
            }
        }.padding(32).frame(width: 410).background(StudioBackdrop())
    }
}
