import Foundation

/// DDC/CI VCP feature codes (VESA MCCS).
/// The only controls the app ever writes over DDC/CI: the brightness and
/// contrast Acer documents in its Picture menu. Its manual warns that
/// "improper adjustment of other controls may result in damage".
public enum DDCPolicy {
    public static let writable: Set<UInt8> = [VCP.brightness, VCP.contrast]
}

public enum VCP {
    public static let brightness: UInt8 = 0x10
    public static let contrast: UInt8 = 0x12
    /// Colour preset (non-continuous): see `ColorPreset`.
    public static let colorPreset: UInt8 = 0x14
    public static let volume: UInt8 = 0x62
    public static let powerMode: UInt8 = 0xD6

    /// MCCS names for controls worth showing a person.
    public static let knownNames: [UInt8: String] = [
        0x10: "Brightness", 0x12: "Contrast", 0x14: "Colour presets",
        0x16: "Red gain", 0x18: "Green gain", 0x1A: "Blue gain",
        0x60: "Input source", 0x62: "Volume", 0x72: "Gamma", 0x87: "Sharpness",
        0x8D: "Mute", 0xD6: "Power mode", 0xDC: "Picture modes"
    ]

    public static func name(_ code: UInt8) -> String {
        switch code {
        case brightness: return "Brightness"
        case contrast: return "Contrast"
        case colorPreset: return "Colour preset"
        default: return String(format: "VCP 0x%02X", code)
        }
    }
}

/// MCCS values for VCP 0x14.
public enum ColorPreset: UInt16, Sendable {
    case sRGB = 0x01
    case native = 0x02
    case k5000 = 0x04
    case k6500 = 0x05
    case k9300 = 0x08
    case user1 = 0x0B

    /// MCCS name for any VCP 0x14 value, including ones without a case here.
    public static func name(_ raw: UInt16) -> String {
        let names: [UInt16: String] = [
            0x01: "sRGB", 0x02: "Native", 0x03: "4000 K", 0x04: "5000 K", 0x05: "6500 K",
            0x06: "7500 K", 0x07: "8200 K", 0x08: "9300 K", 0x09: "10000 K", 0x0A: "11500 K",
            0x0B: "User 1", 0x0C: "User 2", 0x0D: "User 3"
        ]
        return names[raw] ?? String(format: "0x%02X", raw)
    }

    public var label: String {
        switch self {
        case .sRGB: return "sRGB"
        case .native: return "Native"
        case .k5000: return "5000 K"
        case .k6500: return "6500 K"
        case .k9300: return "9300 K"
        case .user1: return "User 1"
        }
    }
}

/// A colour profile choice for ColorSync.
public enum ProfileChoice: Hashable, Codable, Sendable {
    /// The display's own profile (made from its EDID, or the factory one).
    case factory
    /// A profile from /System/Library/ColorSync/Profiles, by file name.
    case system(String)

    public static let sRGBFile = "sRGB Profile.icc"

    public var label: String {
        switch self {
        case .factory: return "Display's own profile"
        case .system(let file): return (file as NSString).deletingPathExtension
        }
    }
}

public struct DDCTarget: Hashable, Codable, Sendable {
    public enum Value: Hashable, Codable, Sendable {
        /// Percent of the control's range (scaled to the monitor's maximum).
        case percent(Int)
        /// An exact value (non-continuous controls like the colour preset).
        case raw(UInt16)
    }

    public var vcp: UInt8
    public var value: Value

    public init(vcp: UInt8, value: Value) { self.vcp = vcp; self.value = value }

    public func rawValue(max: UInt16) -> UInt16 {
        switch value {
        case .raw(let v): return Swift.min(v, max)
        case .percent(let p):
            let clamped = Swift.max(0, Swift.min(100, p))
            return UInt16((Double(clamped) / 100 * Double(max)).rounded())
        }
    }
}

/// Something the app changes itself.
public enum Change: Hashable, Codable, Sendable {
    case mode(DisplayMode)
    case colorProfile(ProfileChoice)
    case ddc(DDCTarget)
    case nightShift(enabled: Bool)
}

public struct PlannedChange: Hashable, Sendable, Identifiable {
    public var id: String
    public var change: Change
    public var title: String
    /// "current → new".
    public var detail: String
    public var why: String
    /// Ticked by default. Optional suggestions start unticked.
    public var onByDefault: Bool
    /// Applies to every screen (Night Shift), not just this one.
    public var isGlobal: Bool = false
    public var isExperimental: Bool = false

    public init(id: String, change: Change, title: String, detail: String, why: String, onByDefault: Bool,
                isGlobal: Bool = false, isExperimental: Bool = false) {
        self.id = id
        self.change = change
        self.title = title
        self.detail = detail
        self.why = why
        self.onByDefault = onByDefault
        self.isGlobal = isGlobal
        self.isExperimental = isExperimental
    }
}

/// Something the person has to do: in the monitor's menu, in System Settings,
/// or in their editing app.
public struct ManualStep: Hashable, Sendable, Identifiable {
    public enum Place: String, Sendable {
        case monitorMenu = "Monitor menu"
        case systemSettings = "System Settings"
        case apps = "Your apps"
        case hardware = "Cable & setup"
    }

    public var id: String { place.rawValue + setting }
    public var place: Place
    public var setting: String
    public var value: String
    public var path: String
    public var why: String
    public var sources: [Source]
}

public struct Recommendation: Sendable {
    public var useCase: UseCase
    public var displayID: UInt32
    public var profile: MonitorProfile?
    public var headline: String
    public var changes: [PlannedChange]
    public var manualSteps: [ManualStep]
    public var warnings: [String]
    /// Background facts about this monitor ("good to know").
    public var notes: [String]
    /// Modes to offer in the picker for the mode change.
    public var modeOptions: [DisplayMode]
    public var sources: [Source]
}
