import AppKit
import SwiftUI
import TunerCore

struct DisplayDetailView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts

    var body: some View {
        let recommendation = model.recommendation(for: display)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderView(display: display, profile: recommendation.profile)
                FactsView(display: display, profile: recommendation.profile)

                VStack(alignment: .leading, spacing: 10) {
                    Text("What are you doing?").font(.title3.bold())
                    UseCasePicker(display: display)
                    HStack {
                        Text("Room lighting")
                        Picker("Room lighting", selection: $model.lighting) {
                            ForEach(RoomLighting.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                    .font(.callout)
                }

                ForEach(recommendation.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ChangesView(display: display, recommendation: recommendation)
                ResultsView()
                ManualStepsView(steps: recommendation.manualSteps)

                if !recommendation.notes.isEmpty {
                    Section {
                        ForEach(recommendation.notes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text("Good to know").font(.title3.bold())
                    }
                }

                ResearchView(recommendation: recommendation)
                RestoreView()
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

// MARK: - Header and facts

private struct HeaderView: View {
    let display: DisplayFacts
    let profile: MonitorProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(display.name).font(.largeTitle.bold())
            if let profile {
                Label("Researched model: \(profile.displayName)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not in the research database yet. Settings come from what this display reports about itself.",
                      systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FactsView: View {
    let display: DisplayFacts
    let profile: MonitorProfile?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            if let specs = profile?.specs {
                row("Panel", "\(specs.size) \(specs.panel.rawValue), \(specs.native)")
                row("Refresh", specs.maxRefresh)
                row("Colour", specs.gamut)
                if let hdr = specs.hdr { row("HDR", hdr) }
                if let vrr = specs.vrr { row("Variable refresh", vrr) }
            }
            if let mode = display.currentMode, display.mirrorOf == nil {
                row("Now", mode.label)
            }
            if let primaries = display.primaries {
                row("Gamut (from EDID)",
                    String(format: "%.0f%% of sRGB, %.0f%% of Display P3",
                           primaries.coverage(of: .sRGB) * 100, primaries.coverage(of: .displayP3) * 100))
            }
            row("Colour profile", display.customProfilePath == nil
                ? "\(display.profileName ?? "Display's own") (display's own)"
                : (display.profileName ?? display.customProfilePath ?? "Custom"))
            row("DDC/CI", ddcText)
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var ddcText: String {
        switch display.ddc {
        case .unknown, .probing: return "Checking…"
        case .unavailable: return display.isBuiltIn ? "Not needed" : "Not available (use the monitor's buttons)"
        case .available(let values):
            let parts = [VCP.brightness, VCP.contrast].compactMap { vcp in
                values[vcp].map { "\(VCP.name(vcp).lowercased()) \($0.percent)%" }
            }
            return "Working" + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", "))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

// MARK: - Use case

private struct UseCasePicker: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts

    var body: some View {
        let selected = model.useCase(for: display.id)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
            ForEach(UseCase.allCases) { useCase in
                Button {
                    model.setUseCase(useCase, for: display.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: useCase.symbol).font(.title2)
                        Text(useCase.title).font(.headline)
                        Text(useCase.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .padding(12)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(useCase == selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(useCase == selected ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Changes the app makes

private struct ChangesView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts
    let recommendation: Recommendation

    var body: some View {
        let changes = model.changes(for: display)
        VStack(alignment: .leading, spacing: 12) {
            Text("The app will change").font(.title3.bold())

            if !recommendation.modeOptions.isEmpty {
                HStack {
                    Text("Mode")
                    Picker("Mode", selection: modeBinding) {
                        ForEach(recommendation.modeOptions) { mode in
                            Text(mode.label).tag(Optional(mode))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 340)
                }
                .font(.callout)
            }

            if changes.isEmpty {
                Label("Nothing to change here: it's already set for \(recommendation.useCase.title.lowercased()).",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(changes) { change in
                    Toggle(isOn: toggleBinding(change)) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(change.title).fontWeight(.semibold)
                                if change.isGlobal { tag("All screens") }
                                if change.isExperimental { tag("Experimental") }
                            }
                            Text(change.detail).monospacedDigit()
                            Text(change.why)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            HStack {
                Button {
                    Task { await model.apply(to: [display.id]) }
                } label: {
                    Label("Apply to \(display.name)", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || !changes.contains { model.isOn($0, for: display) })

                if model.isBusy { ProgressView().controlSize(.small) }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var modeBinding: Binding<DisplayMode?> {
        Binding(
            get: { model.pickerMode(for: display) },
            set: { if let mode = $0 { model.chooseMode(mode, for: display) } })
    }

    private func toggleBinding(_ change: PlannedChange) -> Binding<Bool> {
        Binding(get: { model.isOn(change, for: display) },
                set: { model.setOn($0, change, for: display) })
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }
}

private struct ResultsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !model.results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.results) { result in
                    Label {
                        Text(result.display.isEmpty ? result.title : "\(result.display) · \(result.title)").fontWeight(.medium)
                            + Text("  \(result.message)").foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(result.ok ? .green : .orange)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
        }
    }
}

// MARK: - Steps for the person

private struct ManualStepsView: View {
    let steps: [ManualStep]

    private let order: [ManualStep.Place] = [.monitorMenu, .systemSettings, .hardware, .apps]

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Do these yourself").font(.title3.bold())
                Text("Only the monitor's own menu, System Settings or your apps can change these. Do them right after applying.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(order, id: \.self) { place in
                    let group = steps.filter { $0.place == place }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(place.rawValue, systemImage: icon(place)).font(.headline)
                                Spacer()
                                if place == .systemSettings {
                                    Button("Open Displays Settings") {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                            ForEach(group) { step in StepRow(step: step) }
                        }
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func icon(_ place: ManualStep.Place) -> String {
        switch place {
        case .monitorMenu: return "slider.horizontal.3"
        case .systemSettings: return "gearshape"
        case .apps: return "app.badge"
        case .hardware: return "cable.connector"
        }
    }
}

private struct StepRow: View {
    let step: ManualStep

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text(step.setting).fontWeight(.semibold) + Text(" → ") + Text(step.value).fontWeight(.semibold).foregroundColor(.accentColor))
            Text(step.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(step.why)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !step.sources.isEmpty {
                HStack(spacing: 10) {
                    ForEach(step.sources) { source in
                        if let url = URL(string: source.url) {
                            Link(source.title, destination: url)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.leading, 28)
    }
}

// MARK: - Research and restore

private struct ResearchView: View {
    let recommendation: Recommendation

    var body: some View {
        let sources = allSources
        if !sources.isEmpty || recommendation.profile != nil {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    if let profile = recommendation.profile {
                        Text(profile.confidence)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                    }
                    ForEach(sources) { source in
                        if let url = URL(string: source.url) {
                            Link(source.title, destination: url).font(.callout)
                        }
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Research and sources").font(.title3.bold())
            }
        }
    }

    private var allSources: [Source] {
        var seen = Set<String>()
        let all = (recommendation.profile?.sources ?? []) + recommendation.sources
        return all.filter { seen.insert($0.url).inserted }
    }
}

private struct RestoreView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.undoLastApply() }
            } label: {
                Label("Undo Last Apply", systemImage: "arrow.uturn.backward")
            }
            .disabled(model.lastSnapshot == nil || model.isBusy)

            Button {
                Task { await model.restoreOriginals() }
            } label: {
                Label("Restore Settings From Before Display Tuner", systemImage: "clock.arrow.circlepath")
            }
            .disabled(model.originalSnapshot == nil || model.isBusy)
        }
        .padding(.top, 4)
    }
}
