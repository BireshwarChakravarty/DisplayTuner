import Foundation

/// Where a fact comes from.
public struct Source: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var url: String

    public init(id: String, title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public enum DDCSupport: String, Codable, Sendable {
    case supported, notSupported, unknown
}

/// What the engine needs to know about the monitor's own controls.
public struct MonitorSpecs: Hashable, Codable, Sendable {
    /// The monitor offers an sRGB colour space in its own menu.
    public var hasSRGBColorSpace: Bool
    /// Only a fallback for when macOS can't read the panel's primaries.
    public var isWideGamut: Bool
    public var ddc: DDCSupport
}

/// One researched fact, with the model it was confirmed on (when that isn't
/// the V5 itself) and its sources.
public struct Fact: Hashable, Codable, Sendable, Identifiable {
    public var label: String
    public var value: String
    /// "Measured on the XV272K V3", "Acer's XV275K manual", …
    public var basis: String
    public var sourceIDs: [String]

    public var id: String { label }

    public init(_ label: String, _ value: String, basis: String, sources: [String]) {
        self.label = label
        self.value = value
        self.basis = basis
        self.sourceIDs = sources
    }
}

/// A setting that only the monitor's own on-screen menu can change.
public struct OSDStep: Hashable, Codable, Sendable {
    public var useCases: Set<UseCase>
    public var setting: String
    public var value: String
    /// Where to find it, e.g. "Menu → Gaming → Over Drive".
    public var path: String
    public var why: String
    public var sourceIDs: [String]
}

/// The monitor and everything confirmed about it.
public struct MonitorProfile: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    /// Lower-case substrings of the name macOS reports (from the EDID).
    public var namePatterns: [String]
    /// EDID manufacturer IDs (CGDisplayVendorNumber), used only to break ties.
    public var vendorIDs: [UInt32]
    public var specs: MonitorSpecs
    public var facts: [Fact]
    public var osd: [OSDStep]
    public var notes: [String]
    public var sources: [Source]
    /// How sure the research is and what couldn't be confirmed.
    public var confidence: String

    public func source(_ id: String) -> Source? { sources.first { $0.id == id } }
}

/// The research behind Display Tuner. It covers one monitor, the Acer Nitro
/// XV272K V5. Every fact below was read in the cited source; where the V5's
/// own documentation couldn't be obtained, the fact names the sibling model
/// it comes from.
public enum KnowledgeBase {
    public static func match(name: String, vendorID: UInt32) -> MonitorProfile? {
        let lower = name.lowercased()
        let hits = profiles.filter { profile in profile.namePatterns.contains { lower.contains($0) } }
        if hits.count > 1, let byVendor = hits.first(where: { $0.vendorIDs.contains(vendorID) }) { return byVendor }
        return hits.first
    }

    public static let profiles: [MonitorProfile] = [acerXV272KV5]

    // MARK: Acer Nitro XV272K V5

    /// EDID manufacturer "ACR".
    static let acerVendorID: UInt32 = 0x0472

    /// Use cases that want the panel's native colour and full brightness range.
    private static let native: Set<UseCase> = [.competitiveGaming, .immersiveGaming, .macbookLook, .maxBrightness, .everyday]
    private static let editing: Set<UseCase> = [.photoEditing, .videoEditing]

    public static let acerXV272KV5 = MonitorProfile(
        id: "acer-xv272k-v5",
        displayName: "Acer Nitro XV272K V5",
        namePatterns: ["xv272k"],
        vendorIDs: [acerVendorID],
        specs: MonitorSpecs(hasSRGBColorSpace: true, isWideGamut: true, ddc: .supported),
        facts: [
            Fact("HDR certification", "VESA DisplayHDR 400 (CTS 1.1)",
                 basis: "VESA's list of certified products names the XV272K V5",
                 sources: ["vesa-displayhdr-list"]),
            Fact("4K at 160 Hz", "DisplayPort or USB-C only; set System → Max Refresh Rate to 160Hz",
                 basis: "Acer's XV275K manual, the closest model with the same DFR switch",
                 sources: ["acer-manual-xv275k"]),
            Fact("DFR", "Switches between 3840 × 2160 at 160 Hz and 1920 × 1080 at 320 Hz",
                 basis: "Acer's XV275K manual", sources: ["acer-manual-xv275k"]),
            Fact("Max Brightness", "Picture menu, Off by default: \"The default brightness is set to a low level to save energy\"",
                 basis: "Acer's XV275K manual", sources: ["acer-manual-xv275k"]),
            Fact("Max Brightness Off vs On", "Brightness 100 gave 139 cd/m² Off and 280 cd/m² On",
                 basis: "Measured on the XV282K KV", sources: ["pcmonitors-xv282k"]),
            Fact("Brightness range", "40.1 cd/m² at Brightness 0 to 388.7 cd/m² at Brightness 100",
                 basis: "Measured on the XV272K V3", sources: ["danawa-xv272kv3"]),
            Fact("Static contrast", "1043:1 at Brightness 100",
                 basis: "Measured on the XV272K V3", sources: ["danawa-xv272kv3"]),
            Fact("Native gamut", "94.52% of P3 and 99.96% of sRGB in the default mode",
                 basis: "Measured on the XV272K V3", sources: ["danawa-xv272kv3"]),
            Fact("HDR peak", "332 cd/m² on a 10% window, below the 388.7 cd/m² SDR maximum",
                 basis: "Measured on the XV272K V3", sources: ["danawa-xv272kv3"]),
            Fact("Colour Space", "General by default; sRGB, Rec.709, DCI, EBU, SMPTE-C and HDR also offered",
                 basis: "Acer's XV275K manual", sources: ["acer-manual-xv275k"]),
            Fact("sRGB accuracy", "Average ΔE00 1.03 in the sRGB colour space (3.04 in the default mode)",
                 basis: "Measured on the XV272K V3", sources: ["danawa-xv272kv3"]),
            Fact("Gamma", "2.2 by default", basis: "Acer's XV275K manual", sources: ["acer-manual-xv275k"]),
            Fact("Colour Temp.", "Warm by default; measured 6067 K at default",
                 basis: "Acer's XV275K manual; measured on the XV272K V3",
                 sources: ["acer-manual-xv275k", "danawa-xv272kv3"]),
            Fact("Contrast", "50 by default; calibrations used 48–49",
                 basis: "Measured on the XV273K; calibrations of the XV272U KV, VX282K and XV273K",
                 sources: ["tftcentral-xv273k", "tomshw-xv272u"]),
            Fact("Over Drive overshoot", "Off 0%, Normal 13.7%, Extreme 85.5% (response 5.2 / 3 / 1.7 ms)",
                 basis: "Measured on the XV272K V3 at 160 Hz", sources: ["danawa-xv272kv3"]),
            Fact("ACM", "Dynamic contrast, Off by default", basis: "Acer's XV275K and XV272U V manuals",
                 sources: ["acer-manual-xv275k", "acer-manual-xv272uv"])
        ],
        osd: [
            OSDStep(
                useCases: native,
                setting: "Color Space", value: "General",
                path: "Menu → Color → Color Space",
                why: "General is the factory default and keeps the panel's native colour, which the display's own profile in macOS describes. Acer: any Color Space other than HDR sets Modes to Standard.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: editing,
                setting: "Color Space", value: "sRGB",
                path: "Menu → Color → Color Space",
                why: "Clamps the panel to sRGB, matching the sRGB profile the app assigns. On the XV272K V3 it measured an average ΔE00 of 1.03. Sibling reviews found Contrast, Gamma and Colour Temp. locked in this colour space, while Brightness stays adjustable.",
                sourceIDs: ["acer-manual-xv275k", "danawa-xv272kv3", "pcmonitors-xv282k"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "Modes", value: "Standard",
                path: "Menu → Color → Modes (or Hot Key 2)",
                why: "Acer's factory default (\"Hot key2 (default: Standard mode)\"). Choosing a Color Space other than HDR returns Modes to Standard.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: native,
                setting: "Max Brightness", value: "On",
                path: "Menu → Picture → Max Brightness",
                why: "Off by default to save energy, which caps the backlight: on the XV282K, Brightness 100 gave 139 cd/m² with it Off and 280 with it On. If your Picture menu has no Max Brightness item, skip this.",
                sourceIDs: ["acer-manual-xv275k", "pcmonitors-xv282k"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "ACM", value: "Off",
                path: "Menu → Picture → ACM",
                why: "ACM is Acer's dynamic contrast: it adjusts \"based on the current screen\". It's off by default, and PCMonitors found it biased towards high brightness on mixed content.",
                sourceIDs: ["acer-manual-xv272uv", "acer-manual-xv275k", "pcmonitors-xv282k"]),
            OSDStep(
                useCases: Set(UseCase.allCases).subtracting([.competitiveGaming]),
                setting: "Black Boost", value: "0",
                path: "Menu → Picture → Black Boost",
                why: "Acer: Black Boost \"enhance[s] shadows by increasing the brightness without changing the lighter areas\". At 0, shadows are shown as the signal has them.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: [.competitiveGaming],
                setting: "Black Boost", value: "0, or higher if dark areas hide detail",
                path: "Menu → Picture → Black Boost",
                why: "Acer: Black Boost \"enhance[s] shadows by increasing the brightness without changing the lighter areas\" (scale 0–10). It trades shadow depth for visibility.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "HDR", value: "Off",
                path: "Menu → Picture → HDR",
                why: "For standard-range content. The options are Off and Auto; with HDR on, Acer greys out Contrast, Gamma, ACM and Black Boost.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: native,
                setting: "Gamma", value: "2.2",
                path: "Menu → Color → Gamma",
                why: "Acer's factory default.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: native,
                setting: "Color Temp.", value: "Warm (factory default)",
                path: "Menu → Color → Color Temp.",
                why: "Acer's default. The XV272K V3 measured 6067 K at default, a little warmer than the D65 (about 6500 K) white of sRGB and Display P3. Normal and Cool weren't measured in any review found, so the app doesn't recommend them.",
                sourceIDs: ["acer-manual-xv275k", "danawa-xv272kv3", "apple-display-p3"]),
            OSDStep(
                useCases: native,
                setting: "Over Drive", value: "Normal",
                path: "Menu → Gaming → Over Drive",
                why: "On the XV272K V3 at 160 Hz, Normal overshot 13.7% for a 3 ms response and Extreme 85.5% for 1.7 ms. Large overshoot shows as trails behind moving objects. TFTCentral found Extreme best on the XV273K at 120–144 Hz, so it may be worth trying.",
                sourceIDs: ["danawa-xv272kv3", "tftcentral-xv273k"]),
            OSDStep(
                useCases: native,
                setting: "Variable Refresh Rate", value: "On",
                path: "Menu → Gaming → Variable Refresh Rate",
                why: "Lets a source that supports Adaptive-Sync vary the refresh rate. On older XV272 models (FreeSync Premium in the menu), turning it on locks Over Drive to Normal.",
                sourceIDs: ["acer-manual-xv275k", "acer-manual-xv272uv"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "Max Refresh Rate", value: "160Hz",
                path: "Menu → System → Max Refresh Rate",
                why: "Acer: \"Setting max refresh rate to select OSD Menu > System > Max Refresh Rate > 160Hz.\" 4K at 160 Hz works over DisplayPort or USB-C.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: [.competitiveGaming],
                setting: "DFR", value: "On only for 1080p at 320 Hz",
                path: "Menu → System → DFR (or the DFR hot key)",
                why: "Acer: \"DFR: Switch UHD 160Hz & FHD 320Hz resolution.\" It halves the resolution for twice the refresh rate.",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "DSC", value: "On (factory default)",
                path: "Menu → System → DSC",
                why: "Acer: with DSC Off the monitor \"may not be able to display 4K-(144/146)Hz\".",
                sourceIDs: ["acer-manual-xv275k"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "DDC/CI", value: "On",
                path: "Menu → System → DDC/CI",
                why: "Acer: \"Support monitor settings through software on your PC.\" Display Tuner uses it for brightness and contrast only.",
                sourceIDs: ["acer-manual-xv275k"])
        ],
        notes: [
            "Display Tuner changes only brightness and contrast over DDC/CI. Acer's manual warns: \"Adjust only those controls that are covered by the operating instructions, since improper adjustment of other controls may result in damage.\"",
            "No instrumented review of the XV272K V5 itself exists yet, so measured figures come from its siblings, the XV272K V3 above all, and are labelled with the model."
        ],
        sources: [
            Source(id: "vesa-displayhdr-list", title: "VESA: DisplayHDR certified products (Acer XV272K V5 under DisplayHDR 400)",
                   url: "https://displayhdr.org/certified-products/"),
            Source(id: "acer-manual-xv275k", title: "Acer XV275K user guide, 2024 (closest model with the V5's DFR switch)",
                   url: "https://global-download.acer.com/GDFiles/Document/User%20Manual/User%20Manual_Acer_1.0_A_A.pdf?acerid=638769326554563998&Step1=&Step2=&Step3=XV275KP5&OS=ALL&LC=en&BC=ACER&SC=PA_6"),
            Source(id: "acer-manual-xv272kv3", title: "Acer XV272K V3 user guide, 2023 (Japanese)",
                   url: "https://global-download.acer.com/GDFiles/Document/User%20Manual/User%20Manual_Acer_1.0_A_A.pdf?acerid=638373664951374988&Step1=&Step2=&Step3=XV272KV3&OS=ALL&LC=en&BC=ACER&SC=PA_6"),
            Source(id: "acer-manual-xv272uv", title: "Acer XV272U V user guide, 2018",
                   url: "https://global-download.acer.com/GDFiles/Document/User%20Manual/User%20Manual_Acer_1.0_A_A.pdf?acerid=637376339193437048&Step1=MONITOR&Step2=XV+SERIES&Step3=XV272UV&OS=ALL&LC=en&BC=ACER&SC=PA_6"),
            Source(id: "danawa-xv272kv3", title: "CoolEnjoy / Danawa: Acer XV272K V3 measured review (Korean)",
                   url: "https://dpg.danawa.com/news/view?boardSeq=62&listSeq=5612150"),
            Source(id: "pcmonitors-xv282k", title: "PCMonitors: Acer XV282K KV review (Max Brightness, ACM, sRGB)",
                   url: "https://pcmonitors.info/reviews/acer-xv282k-kv/"),
            Source(id: "tftcentral-xv273k", title: "TFTCentral: Acer Nitro XV273K review (defaults, Over Drive)",
                   url: "https://tftcentral.co.uk/reviews/acer_nitro_xv273k.htm"),
            Source(id: "tomshw-xv272u", title: "Tom's Hardware: Acer Nitro XV272U KV review (calibrated settings)",
                   url: "https://www.tomshardware.com/reviews/acer-nitro-xv272u-kvbmiiprzx-review"),
            Source(id: "apple-display-p3", title: "Apple Developer: Display P3 (D65 white point, sRGB transfer function)",
                   url: "https://developer.apple.com/documentation/coregraphics/cgcolorspace/displayp3")
        ],
        confidence: "Acer's manual for the XV272K V5 couldn't be downloaded, so menu paths and defaults come from Acer's 2024 XV275K manual, the closest model with the same 4K 160 Hz / 1080p 320 Hz switch; older XV272 manuals name some items differently. No instrumented review of the V5 exists yet, so measurements are from siblings and say which. Your unit's menu may differ slightly."
    )

    // MARK: General research

    public static let generalSources: [Source] = [
        Source(id: "apple-vrr", title: "Apple: Use an Adaptive Sync external display with your Mac",
               url: "https://support.apple.com/en-us/102144"),
        Source(id: "apple-hdr", title: "Apple: Play HDR video on your Mac (HDR10 external displays)",
               url: "https://support.apple.com/en-us/102205"),
        Source(id: "apple-frame-rate", title: "Apple: choose a refresh rate that divides evenly into the frame rate",
               url: "https://support.apple.com/en-us/102297"),
        Source(id: "apple-night-shift", title: "Apple: Use Night Shift on your Mac",
               url: "https://support.apple.com/en-us/102191"),
        Source(id: "apple-macbook-air-m4", title: "Apple: MacBook Air (13-inch, M4) tech specs",
               url: "https://support.apple.com/en-us/122209"),
        Source(id: "apple-studio-display", title: "Apple: Studio Display tech specs (218 pixels per inch)",
               url: "https://support.apple.com/en-us/111890"),
        Source(id: "rtings-contrast", title: "RTINGS: contrast ratio (LCD backlight moves black and white together)",
               url: "https://www.rtings.com/monitor/tests/picture-quality/contrast-ratio"),
        Source(id: "w3c-srgb", title: "W3C: sRGB (80 cd/m² reference white, D65)",
               url: "https://www.w3.org/Graphics/Color/sRGB.html"),
        Source(id: "canon-brightness", title: "Canon: monitor brightness for printing (around 120 cd/m²)",
               url: "https://ij.manual.canon/ij/webmanual/PrintStudioPro/W/1.4/AR/DPPG/dppg_2-03.html"),
        Source(id: "photoreview-prints", title: "Photo Review / BenQ: 80–120 cd/m² for print work",
               url: "https://www.photoreview.com.au/featured/how-to-achieve-prints-with-the-right-brightness-colour-and-tonality/"),
        Source(id: "itu-bt2035", title: "ITU-R BT.2035: 100 cd/m² reference white in a 10 lux room",
               url: "https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.2035-0-201307-I!!PDF-E.pdf")
    ]

    public static func generalSource(_ id: String) -> Source? { generalSources.first { $0.id == id } }
}
