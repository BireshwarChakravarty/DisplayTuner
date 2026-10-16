import Foundation

/// The settings of one display before the app changed them.
public struct DisplaySnapshot: Codable, Hashable, Sendable {
    /// DisplayFacts.key (vendor-product-serial): survives reconnects.
    public var key: String
    public var name: String
    public var mode: DisplayMode?
    /// Whether a custom ColorSync profile was assigned, and which.
    public var hadCustomProfile: Bool
    public var customProfilePath: String?
    /// DDC values (raw) for the controls the app may change.
    public var capturesProfile: Bool
    public var ddc: [UInt8: UInt16]

    public init(key: String, name: String, mode: DisplayMode?, hadCustomProfile: Bool,
                customProfilePath: String?, ddc: [UInt8: UInt16], capturesProfile: Bool = true) {
        self.key = key
        self.name = name
        self.mode = mode
        self.hadCustomProfile = hadCustomProfile
        self.customProfilePath = customProfilePath
        self.ddc = ddc
        self.capturesProfile = capturesProfile
    }
    enum CodingKeys: String, CodingKey { case key, name, mode, hadCustomProfile, customProfilePath, ddc, capturesProfile }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decodeIfPresent(DisplayMode.self, forKey: .mode)
        hadCustomProfile = try c.decode(Bool.self, forKey: .hadCustomProfile)
        customProfilePath = try c.decodeIfPresent(String.self, forKey: .customProfilePath)
        ddc = try c.decode([UInt8: UInt16].self, forKey: .ddc)
        capturesProfile = try c.decodeIfPresent(Bool.self, forKey: .capturesProfile) ?? true
    }

}

/// Everything needed to undo an apply.
public struct Snapshot: Codable, Hashable, Sendable {
    public var date: Date
    public var displays: [DisplaySnapshot]
    public var nightShiftEnabled: Bool?

    public init(date: Date = Date(), displays: [DisplaySnapshot], nightShiftEnabled: Bool?) {
        self.date = date
        self.displays = displays
        self.nightShiftEnabled = nightShiftEnabled
    }

    public func display(_ key: String) -> DisplaySnapshot? { displays.first { $0.key == key } }

    /// Fold `newer` into this snapshot, keeping this one's values wherever it
    /// already has them. Used for "settings from before Display Tuner": the
    /// first value seen for each control is the original.
    public func keepingOriginals(addingFrom newer: Snapshot) -> Snapshot {
        var merged = self
        for display in newer.displays {
            if let index = merged.displays.firstIndex(where: { $0.key == display.key }) {
                for (vcp, value) in display.ddc where merged.displays[index].ddc[vcp] == nil {
                    merged.displays[index].ddc[vcp] = value
                }
                if !merged.displays[index].capturesProfile && display.capturesProfile {
                    merged.displays[index].hadCustomProfile = display.hadCustomProfile
                    merged.displays[index].customProfilePath = display.customProfilePath
                    merged.displays[index].capturesProfile = true
                }
                if merged.displays[index].mode == nil { merged.displays[index].mode = display.mode }
            } else {
                merged.displays.append(display)
            }
        }
        if merged.nightShiftEnabled == nil { merged.nightShiftEnabled = newer.nightShiftEnabled }
        return merged
    }
}
