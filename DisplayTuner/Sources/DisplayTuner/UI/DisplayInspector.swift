import SwiftUI
import TunerCore

/// The trailing inspector: the display's colour gamut, specifications, what
/// the app knows about it, and every source the advice comes from.
struct DisplayInspector: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayFacts
    let rec: Recommendation

    var body: some View {
        Form {
            Section("Colour Gamut") {
                GamutDiagram(primaries: display.primaries)
                    .frame(maxWidth: 260)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                if let primaries = display.primaries {
                    LabeledContent("sRGB", value: percent(primaries.coverage(of: .sRGB)))
                    LabeledContent("Display P3", value: percent(primaries.coverage(of: .displayP3)))
                }
            }

            if let specs = rec.profile?.specs {
                Section("Specifications") {
                    LabeledContent("Panel", value: "\(specs.size) \(specs.panel.rawValue)")
                    LabeledContent("Resolution", value: specs.native)
                    LabeledContent("Refresh rate", value: specs.maxRefresh)
                    LabeledContent("Colour", value: specs.gamut)
                    if let nits = specs.peakSDRNits { LabeledContent("Rated brightness", value: "\(Int(nits)) cd/m²") }
                    if let hdr = specs.hdr { LabeledContent("HDR", value: hdr) }
                    if let vrr = specs.vrr { LabeledContent("Variable refresh", value: vrr) }
                }
            }

            Section("This Mac Sees") {
                if let mode = display.currentMode { LabeledContent("Mode", value: mode.label) }
                LabeledContent("Colour profile", value: profileText)
                LabeledContent("DDC/CI", value: ddcText)
                if let caps = display.capabilities {
                    LabeledContent("Monitor reports") {
                        Text(caps.describedControls.joined(separator: ", ")).multilineTextAlignment(.trailing)
                    }
                }
            }

            if !rec.notes.isEmpty {
                Section("Notes") {
                    ForEach(rec.notes, id: \.self) { note in
                        Text(note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let profile = rec.profile {
                Section {
                    Text(profile.confidence).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(sources) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                Label(source.title, systemImage: "link").multilineTextAlignment(.leading)
                            }
                        }
                    }
                } header: {
                    Text("Research and Sources")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private var profileText: String {
        display.customProfilePath == nil
            ? (display.profileName ?? "Display's own")
            : (display.profileName ?? display.customProfilePath ?? "Custom")
    }

    private var ddcText: String {
        switch display.ddc {
        case .unknown, .probing: return "Checking…"
        case .unavailable: return display.isBuiltIn ? "Not needed" : "Not available"
        case .available(let values):
            let parts = [VCP.brightness, VCP.contrast].compactMap { vcp in values[vcp].map { "\(VCP.name(vcp).lowercased()) \($0.percent)%" } }
            return parts.isEmpty ? "Connected" : parts.joined(separator: ", ")
        }
    }

    private var sources: [Source] {
        var seen = Set<String>()
        return ((rec.profile?.sources ?? []) + rec.sources).filter { seen.insert($0.url).inserted }
    }
}
