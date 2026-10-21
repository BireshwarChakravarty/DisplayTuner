import Foundation

/// Where a recommendation comes from.
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

public enum PanelTech: String, Codable, Sendable {
    case ips = "IPS"
    case va = "VA"
    case tn = "TN"
    case oled = "OLED"
    case miniLED = "Mini-LED IPS"
    case unknown = "Unknown"
}

public enum DDCSupport: String, Codable, Sendable {
    case supported, notSupported, unknown
}

/// Published facts about one monitor model.
public struct MonitorSpecs: Hashable, Codable, Sendable {
    public var panel: PanelTech
    public var size: String
    public var native: String
    public var maxRefresh: String
    public var gamut: String
    public var isWideGamut: Bool
    public var peakSDRNits: Double?
    public var hdr: String?
    public var vrr: String?
    /// Has a picture mode that clamps the panel to sRGB.
    public var hasSRGBMode: Bool
    /// Factory contrast (the setting that doesn't clip whites).
    public var defaultContrast: Int?
    public var ddc: DDCSupport
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

/// A monitor model with researched settings.
public struct MonitorProfile: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    /// Lower-case substrings of the name macOS reports (from the EDID).
    public var namePatterns: [String]
    /// EDID manufacturer IDs (CGDisplayVendorNumber), used only to break ties.
    public var vendorIDs: [UInt32]
    public var specs: MonitorSpecs
    public var osd: [OSDStep]
    public var notes: [String]
    public var sources: [Source]
    /// How sure the research is and what wasn't confirmed.
    public var confidence: String

    public func source(_ id: String) -> Source? { sources.first { $0.id == id } }
}

/// The research database. It starts with the monitors on this desk; any other
/// display gets settings derived from what it reports about itself.
public enum KnowledgeBase {
    public static func match(name: String, vendorID: UInt32) -> MonitorProfile? {
        let lower = name.lowercased()
        let hits = profiles.filter { profile in profile.namePatterns.contains { lower.contains($0) } }
        if hits.count > 1, let byVendor = hits.first(where: { $0.vendorIDs.contains(vendorID) }) { return byVendor }
        return hits.first
    }

    public static let profiles: [MonitorProfile] = [acerXV272KV5, arzopaPortable]

    // MARK: Acer Nitro XV272K V5

    /// EDID manufacturer "ACR".
    static let acerVendorID: UInt32 = 0x0472

    public static let acerXV272KV5 = MonitorProfile(
        id: "acer-xv272k-v5",
        displayName: "Acer Nitro XV272K V5",
        namePatterns: ["xv272k"],
        vendorIDs: [acerVendorID],
        specs: MonitorSpecs(
            panel: .ips,
            size: "27 in",
            native: "3840 × 2160",
            maxRefresh: "160 Hz at 4K; 320 Hz at 1080p with DFR (dual mode)",
            gamut: "Wide: about 90–95% DCI-P3 (≈130% sRGB), with an sRGB mode",
            isWideGamut: true,
            peakSDRNits: 400,
            hdr: "VESA DisplayHDR 400 (no local dimming)",
            vrr: "AMD FreeSync Premium / Adaptive-Sync",
            hasSRGBMode: true,
            defaultContrast: 50,
            ddc: .supported
        ),
        osd: [
            OSDStep(
                useCases: [.competitiveGaming, .immersiveGaming, .macbookLook, .everyday],
                setting: "Mode", value: "Standard (or User)",
                path: "Menu → Color (or Picture) → Mode",
                why: "Uses the full wide gamut and unlocks brightness. Must match the colour profile this preset sets (the monitor's own).",
                sourceIDs: ["displayninja-xv272u"]),
            OSDStep(
                useCases: [.photoEditing, .videoEditing],
                setting: "Mode", value: "sRGB",
                path: "Menu → Color (or Picture) → Mode",
                why: "Clamps the ~130% sRGB native gamut to sRGB, so games, web and other unmanaged content show true colours. Acer lists it as factory-calibrated (Delta E < 1). This preset assigns the matching sRGB profile in macOS.",
                sourceIDs: ["acer-store", "acer-manual", "displayninja-xv272u"]),
            OSDStep(
                useCases: [.competitiveGaming, .immersiveGaming, .macbookLook, .everyday],
                setting: "Over Drive", value: "Normal",
                path: "Menu → Gaming → Over Drive",
                why: "Extreme adds visible overshoot (inverse ghosting) on this Acer IPS family, and Acer forces Normal whenever Adaptive-Sync is on anyway.",
                sourceIDs: ["acer-manual", "displayninja-xv272u", "blurbusters-xv272"]),
            OSDStep(
                useCases: [.competitiveGaming, .immersiveGaming, .macbookLook, .everyday],
                setting: "Adaptive-Sync / FreeSync Premium", value: "On",
                path: "Menu → Gaming → Adaptive-Sync",
                why: "Needed before macOS offers a Variable refresh rate for this screen.",
                sourceIDs: ["acer-manual", "apple-vrr"]),
            OSDStep(
                useCases: [.competitiveGaming],
                setting: "Black Boost", value: "Off, or a low level if dark corners hide enemies",
                path: "Menu → Picture (or Gaming) → Black Boost",
                why: "Lifts shadow detail for visibility at the cost of contrast; it is a visibility aid, not an image-quality setting.",
                sourceIDs: ["itechguides-nitro"]),
            OSDStep(
                useCases: [.immersiveGaming, .photoEditing, .videoEditing, .macbookLook, .everyday],
                setting: "Black Boost", value: "Off / 0",
                path: "Menu → Picture (or Gaming) → Black Boost",
                why: "Any boost raises blacks and flattens contrast, which skews grading and shadow detail.",
                sourceIDs: ["itechguides-nitro"]),
            OSDStep(
                useCases: [.macbookLook],
                setting: "Colour Temp", value: "Normal (try Warm if whites look bluer than your MacBook's)",
                path: "Menu → Color → Color Temp",
                why: "Apple's displays are set to D65 (6500 K). Reviews of this Nitro family measured the default close to that (about 6200–6600 K). Cool looks blue next to a Mac. For a side-by-side check, turn True Tone off on the MacBook.",
                sourceIDs: ["pcworld-xv272", "rtings-xv272u"]),
            OSDStep(
                useCases: [.macbookLook],
                setting: "Gamma", value: "2.2",
                path: "Menu → Color → Gamma",
                why: "The tone curve macOS and Apple's displays use. Other values make midtones look flat or heavy.",
                sourceIDs: ["rtings-xv272u"]),
            OSDStep(
                useCases: [.macbookLook],
                setting: "Saturation / 6-axis colour", value: "Default",
                path: "Menu → Color",
                why: "The vivid look comes from the panel's wide gamut shown accurately. Raising saturation pushes skin tones and skies past what a MacBook shows.",
                sourceIDs: []),
            OSDStep(
                useCases: [.competitiveGaming],
                setting: "DFR (dual mode)", value: "On only if you want 1080p @ 320 Hz",
                path: "Menu → Gaming → DFR",
                why: "Halves the resolution in exchange for twice the refresh rate. Leave it off otherwise; 4K @ 160 Hz is sharper.",
                sourceIDs: ["acer-store"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "Dynamic contrast, ACM, Light Sense, Eco modes", value: "Off",
                path: "Menu → Picture",
                why: "They change brightness on their own, so neither games nor edits look consistent. Auto-brightness and Eco modes are also known causes of flicker with Macs.",
                sourceIDs: ["displaybuddy-flicker"]),
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "DDC/CI", value: "On",
                path: "Menu → System → DDC/CI",
                why: "Lets this app (and Switchboard) set brightness and contrast for you.",
                sourceIDs: ["m1ddc"])
        ],
        notes: [
            "Connect it with a USB-C/Thunderbolt-to-DisplayPort cable for Variable refresh. Apple advises against HDMI for Adaptive-Sync.",
            "It accepts DDC/CI but ignores the factory-reset commands, so contrast is set to its factory 50 directly.",
            "In sRGB mode some monitors lock brightness. After you apply, the app reads it back and tells you."
        ],
        sources: [
            Source(id: "acer-store", title: "Acer Store: Nitro XV272K V5 (160 Hz UHD, 320 Hz FHD via DFR, Delta E < 1)",
                   url: "https://store.acer.com/en-in/acer-nitro-xv272k-v5-27-inch-uhd-3840x2160-ips-agile-splendor-gaming-monitor-160hz-refresh-delta-e-1-fhd-320hz-through-dfr-g-sync-freesync-compatible-smart-dial-eyesafe-certified-black"),
            Source(id: "shi-spec", title: "SHI: Acer Nitro XV272K V5bmiiprx spec sheet",
                   url: "https://www.shi.com/product/49740911/Acer-Nitro-XV272K-V5bmiiprx"),
            Source(id: "acer-manual", title: "Acer Nitro XV-series user guide (Over Drive, Adaptive-Sync, sRGB mode)",
                   url: "https://global-download.acer.com/GDFiles/Document/User%20Manual/User%20Manual_Acer_1.0_A_A.pdf?acerid=637376339193437048&Step1=MONITOR&Step2=XV+SERIES&Step3=XV272UV&OS=ALL&LC=en&BC=ACER&SC=PA_6"),
            Source(id: "displayninja-xv272u", title: "DisplayNinja: Acer XV272U review (Overdrive, sRGB clamp)",
                   url: "https://www.displayninja.com/acer-xv272u-review/"),
            Source(id: "tomshw-xv272u", title: "Tom's Hardware: Acer Nitro XV272U review",
                   url: "https://www.tomshardware.com/reviews/acer-nitro-xv272u-kvbmiiprzx-review"),
            Source(id: "blurbusters-xv272", title: "Blur Busters forum: Acer XV272 hands-on (VRR with Over Drive)",
                   url: "https://forums.blurbusters.com/viewtopic.php?t=11054"),
            Source(id: "pcworld-xv272", title: "PCWorld: Acer Nitro XV272 review (default colour temperature ≈6200 K)",
                   url: "https://www.pcworld.com/article/701844/acer-nitro-xv272-review-top-tier-gaming-on-a-1080p-monitor.html"),
            Source(id: "rtings-xv272u", title: "RTINGS: Acer Nitro XV272U KVbmiiprzx (≈6550 K, gamma 2.2 after calibration)",
                   url: "https://www.rtings.com/monitor/tools/compare/acer-nitro-xv272u-kvbmiiprzx-vs-samsung-odyssey-g51c-s27cg51/23638/39538"),
            Source(id: "itechguides-nitro", title: "iTechGuides: Acer Nitro monitor settings (Black Boost)",
                   url: "https://www.itechguides.com/top-5-acer-nitro-monitor-settings-best-guide/"),
            Source(id: "apple-vrr", title: "Apple: Use an Adaptive Sync external display with your Mac",
                   url: "https://support.apple.com/102144"),
            Source(id: "tftcentral-hdr400", title: "TFTCentral: why DisplayHDR 400 needs to go",
                   url: "https://tftcentral.co.uk/why-your-hdr-monitor-is-probably-not-hdr-at-all-and-why-displayhdr-400-needs-to-go/"),
            Source(id: "displaybuddy-flicker", title: "Fixing external monitor flicker on Mac (auto-brightness, Eco, 48–60 Hz VRR)",
                   url: "https://displaybuddy.app/blog/2026-05-13/fix-monitor-flickering-mac"),
            Source(id: "m1ddc", title: "m1ddc: DDC/CI on Apple Silicon",
                   url: "https://github.com/waydabber/m1ddc")
        ],
        confidence: "Specs are from Acer and retailer listings. No independent review of the V5 itself was found, so the menu paths and the Over Drive advice come from Acer's manuals and reviews of sibling Nitro XV272 models with the same menu system. Menu names on your unit may differ slightly."
    )

    // MARK: ARZOPA portable monitors

    public static let arzopaPortable = MonitorProfile(
        id: "arzopa-portable",
        displayName: "ARZOPA portable monitor",
        namePatterns: ["arzopa"],
        vendorIDs: [],
        specs: MonitorSpecs(
            panel: .ips,
            size: "15.6–16.1 in (by model)",
            native: "1920 × 1080 (Z1FC) or 2560 × 1600 (Z1RC)",
            maxRefresh: "60 Hz (Z1RC) to 144 Hz (Z1FC)",
            gamut: "sRGB class (\"100% sRGB\" claimed)",
            isWideGamut: false,
            peakSDRNits: nil,
            hdr: nil,
            vrr: nil,
            hasSRGBMode: false,
            defaultContrast: nil,
            ddc: .notSupported
        ),
        osd: [
            OSDStep(
                useCases: Set(UseCase.allCases),
                setting: "Brightness", value: "Match the Acer by eye",
                path: "Buttons on the side → Brightness",
                why: "It has no DDC/CI, so nothing on the Mac can set its backlight.",
                sourceIDs: []),
            OSDStep(
                useCases: [.photoEditing, .videoEditing],
                setting: "Picture mode / colour temperature", value: "Standard, Warm or 6500K (whichever exists)",
                path: "Buttons on the side → Color",
                why: "The closest it gets to the D65 white point editing assumes.",
                sourceIDs: ["techradar-z1rc"])
        ],
        notes: [
            "Use it as a reference preview at most. Reviews found ARZOPA panels fine for general use, but not to the colour-accuracy standard creative work expects.",
            "While it mirrors the Acer, the two share one picture. For gaming, switch it off in Switchboard or use Extend so it can't hold the Acer back."
        ],
        sources: [
            Source(id: "techradar-z1rc", title: "TechRadar: Arzopa Z1RC portable monitor review",
                   url: "https://www.techradar.com/pro/arzopa-z1rc-portable-monitor-review"),
            Source(id: "mightygadget-z1rc", title: "Mighty Gadget: Arzopa Z1RC review (vs Z1FC 144 Hz / 300 nits)",
                   url: "https://mightygadget.co.uk/arzopa-z1rc-portable-monitor-review-a-2560x1600-hdr-500nits-8bit-qhd-usb-c-hdmi-laptop-monitor")
        ],
        confidence: "The exact ARZOPA model isn't known, so these are family-level facts. The app reads its real resolution and refresh rate from macOS."
    )

    // MARK: General research used for every display

    public static let generalSources: [Source] = [
        Source(id: "dxo-targets", title: "DxO forum: editing targets (sRGB, gamma 2.2, D65, ≤120 cd/m²; 80–100 for print)",
               url: "https://forum.dxo.com/t/calibrating-monitor-with-photolab-5-in-mind/33809"),
        Source(id: "diyp-calibration", title: "DIYPhotography: monitor calibration for photography",
               url: "https://www.diyphotography.net/monitor-calibration-photography/"),
        Source(id: "apple-vrr", title: "Apple: Use an Adaptive Sync external display with your Mac",
               url: "https://support.apple.com/102144"),
        Source(id: "apple-reference-modes", title: "Apple: reference modes (BT.709/BT.1886 for HD video)",
               url: "https://support.apple.com/108321"),
        Source(id: "rtings-hdr", title: "RTINGS: VESA DisplayHDR certification explained",
               url: "https://www.rtings.com/monitor/learn/display-hdr")
    ]

    public static func generalSource(_ id: String) -> Source? { generalSources.first { $0.id == id } }
}
