import Foundation

/// DDC/CI VCP feature codes (VESA MCCS).
public enum VCP {
    public static let restoreFactoryDefaults: UInt8 = 0x04
    public static let restoreFactoryLuminanceContrast: UInt8 = 0x06
    public static let brightness: UInt8 = 0x10
    public static let contrast: UInt8 = 0x12
    /// Colour preset (non-continuous): see `ColorPreset`.
    public static let colorPreset: UInt8 = 0x14
    public static let volume: UInt8 = 0x62
    public static let powerMode: UInt8 = 0xD6

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

    public func rawValue(max: UInt16) -> UInt16 {
        switch value {
        case .raw(let v): return v
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
