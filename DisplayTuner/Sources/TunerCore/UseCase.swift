import Foundation

/// What the screen is about to be used for. Each one is a preset.
public enum UseCase: String, CaseIterable, Codable, Sendable, Identifiable {
    case competitiveGaming
    case immersiveGaming
    case photoEditing
    case videoEditing
    case macbookLook
    case maxBrightness
    case everyday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .competitiveGaming: return "Competitive Gaming"
        case .immersiveGaming: return "Immersive Gaming"
        case .photoEditing: return "Photo Editing"
        case .videoEditing: return "Video Editing"
        case .macbookLook: return "MacBook Look"
        case .maxBrightness: return "Max Brightness"
        case .everyday: return "Everyday"
        }
    }

    public var subtitle: String {
        switch self {
        case .competitiveGaming: return "Highest refresh, lowest blur"
        case .immersiveGaming: return "Rich colour, smooth VRR"
        case .photoEditing: return "Accurate sRGB colour for photos"
        case .videoEditing: return "Accurate colour, judder-free playback"
        case .macbookLook: return "Bright, wide P3 colour, as on a MacBook"
        case .maxBrightness: return "Full backlight, factory picture"
        case .everyday: return "Native colour at the highest refresh"
        }
    }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .competitiveGaming: return "scope"
        case .immersiveGaming: return "gamecontroller"
        case .photoEditing: return "camera.aperture"
        case .videoEditing: return "film"
        case .macbookLook: return "laptopcomputer"
        case .maxBrightness: return "sun.max.fill"
        case .everyday: return "desktopcomputer"
        }
    }

    public var isEditing: Bool { self == .photoEditing || self == .videoEditing }
    public var isGaming: Bool { self == .competitiveGaming || self == .immersiveGaming }
}

/// How bright the room is. Kept so saved presets still load; brightness
/// targets no longer depend on it, because the V5's brightness curve isn't
/// published and a percentage can't be turned into cd/m² reliably.
public enum RoomLighting: String, CaseIterable, Codable, Sendable, Identifiable {
    case dim
    case normal
    case bright

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dim: return "Dim"
        case .normal: return "Normal"
        case .bright: return "Bright"
        }
    }
}
