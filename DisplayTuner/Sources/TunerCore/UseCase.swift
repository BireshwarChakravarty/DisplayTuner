import Foundation

/// What the screen is about to be used for. Each one is a preset.
public enum UseCase: String, CaseIterable, Codable, Sendable, Identifiable {
    case competitiveGaming
    case immersiveGaming
    case photoEditing
    case videoEditing
    case macbookLook
    case everyday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .competitiveGaming: return "Competitive Gaming"
        case .immersiveGaming: return "Immersive Gaming"
        case .photoEditing: return "Photo Editing"
        case .videoEditing: return "Video Editing"
        case .macbookLook: return "MacBook Look"
        case .everyday: return "Everyday"
        }
    }

    public var subtitle: String {
        switch self {
        case .competitiveGaming: return "Highest refresh, lowest blur"
        case .immersiveGaming: return "Rich colour, smooth VRR"
        case .photoEditing: return "Accurate sRGB at a print-friendly brightness"
        case .videoEditing: return "Rec. 709 grading, judder-free playback"
        case .macbookLook: return "Bright, vivid P3 colour like a Retina display"
        case .everyday: return "Sharp, smooth and comfortable"
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
        case .everyday: return "desktopcomputer"
        }
    }

    public var isEditing: Bool { self == .photoEditing || self == .videoEditing }
    public var isGaming: Bool { self == .competitiveGaming || self == .immersiveGaming }
}

/// The light in the room while editing. Brightness targets follow it.
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

    /// Target white luminance for editing, in cd/m² (nits).
    ///
    /// 120 cd/m² is the common photo-editing target; 80–100 for print matching
    /// or a dim room; brighter rooms need more to avoid editing too dark.
    public func editingNits(for useCase: UseCase) -> Double {
        switch (self, useCase) {
        case (.dim, .videoEditing): return 100   // BT.709/BT.1886 grading reference white
        case (.dim, _): return 90
        case (.normal, _): return 120
        case (.bright, _): return 160
        }
    }

    /// A comfortable white level for games and general use, in cd/m².
    /// There is no standard for this; it is brighter than the editing target
    /// for punch, but well short of an IPS panel's maximum, where blacks glow.
    public var comfortNits: Double {
        switch self {
        case .dim: return 140
        case .normal: return 200
        case .bright: return 280
        }
    }

    /// The MacBook Look: as bright as a MacBook Air screen (500 cd/m² at
    /// full brightness) without being glaring in a dim room.
    public var vividNits: Double {
        switch self {
        case .dim: return 250
        case .normal: return 350
        case .bright: return 500
        }
    }

    /// The white level a preset aims for in this room.
    public func targetNits(for useCase: UseCase) -> Double {
        if useCase.isEditing { return editingNits(for: useCase) }
        if useCase == .macbookLook { return vividNits }
        return comfortNits
    }
}
