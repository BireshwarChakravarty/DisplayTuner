import Foundation

/// One display mode as macOS offers it (mirrors CGDisplayMode).
public struct DisplayMode: Hashable, Codable, Sendable, Identifiable {
    /// CGDisplayModeGetIODisplayModeID.
    public var modeID: Int32
    /// Size in points ("looks like").
    public var width: Int
    public var height: Int
    /// Size of the framebuffer in pixels.
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var usableForDesktop: Bool

    public init(modeID: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int,
                refreshRate: Double, usableForDesktop: Bool = true) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.usableForDesktop = usableForDesktop
    }

    public var id: String { "\(modeID)-\(width)x\(height)-\(pixelWidth)x\(pixelHeight)@\(refreshRate)" }
    public var isHiDPI: Bool { pixelWidth > width }
    public var layout: Layout { Layout(width: width, height: height, pixelWidth: pixelWidth, pixelHeight: pixelHeight) }

    /// Same layout and (within half a hertz) the same refresh rate.
    public func matches(_ other: DisplayMode) -> Bool {
        layout == other.layout && abs(refreshRate - other.refreshRate) < 0.5
    }

    public var refreshLabel: String {
        refreshRate <= 0 ? "default refresh" : "\(Self.hz(refreshRate)) Hz"
    }

    public var label: String { "\(layout.label) at \(refreshLabel)" }

    static func hz(_ value: Double) -> String {
        abs(value.rounded() - value) < 0.05 ? String(Int(value.rounded())) : String(format: "%.2f", value)
    }
}

/// A desktop size: what things look like (points) and how many pixels are drawn.
public struct Layout: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public var isHiDPI: Bool { pixelWidth > width }
    public var label: String { "\(width) × \(height)" + (isHiDPI ? " (HiDPI)" : "") }
}

/// What a monitor reported for a DDC/CI control.
public struct VCPValue: Hashable, Codable, Sendable {
    public var current: UInt16
    public var max: UInt16

    public init(current: UInt16, max: UInt16) {
        self.current = current
        self.max = max
    }

    public var percent: Int { max == 0 ? 0 : Int((Double(current) / Double(max) * 100).rounded()) }
}

public enum DDCStatus: Hashable, Sendable {
    case unknown
    case probing
    case unavailable
    case available([UInt8: VCPValue])

    public var values: [UInt8: VCPValue] {
        if case .available(let values) = self { return values }
        return [:]
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// Everything the app detected about one connected display.
public struct DisplayFacts: Hashable, Sendable, Identifiable {
    public var id: UInt32
    public var persistentID: String?
    public var name: String
    public var vendorID: UInt32
    public var productID: UInt32
    public var serial: UInt32
    public var isBuiltIn: Bool
    /// The display this one mirrors (nil if it isn't a mirror).
    public var mirrorOf: UInt32?
    public var modes: [DisplayMode]
    public var currentMode: DisplayMode?
    /// Physical width in millimetres, if the monitor reports it.
    public var widthMM: Double?
    /// From the active ICC profile.
    public var primaries: Primaries?
    public var profileName: String?
    /// A user-assigned ColorSync profile, if any (nil = factory/EDID profile).
    public var customProfilePath: String?
    /// NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue (> 1 means HDR capable).
    public var edrHeadroom: Double
    public var ddc: DDCStatus

    public init(id: UInt32, name: String, vendorID: UInt32 = 0, productID: UInt32 = 0, serial: UInt32 = 0,
                isBuiltIn: Bool = false, mirrorOf: UInt32? = nil, modes: [DisplayMode] = [],
                currentMode: DisplayMode? = nil, widthMM: Double? = nil, primaries: Primaries? = nil,
                profileName: String? = nil, customProfilePath: String? = nil, edrHeadroom: Double = 1,
                ddc: DDCStatus = .unknown, persistentID: String? = nil) {
        self.id = id
        self.persistentID = persistentID
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.isBuiltIn = isBuiltIn
        self.mirrorOf = mirrorOf
        self.modes = modes
        self.currentMode = currentMode
        self.widthMM = widthMM
        self.primaries = primaries
        self.profileName = profileName
        self.customProfilePath = customProfilePath
        self.edrHeadroom = edrHeadroom
        self.ddc = ddc
    }

    /// Stable key for remembering this monitor across reconnects.
    public var key: String {
        persistentID ?? (serial != 0
            ? String(format: "%04X-%04X-%08X", vendorID, productID, serial)
            : "session-\(id)")
    }

    public var hasCalibration: Bool {
        guard let path = customProfilePath else { return false }
        return !path.hasPrefix("/System/Library/ColorSync/Profiles/")
    }

    public var maxRefresh: Double { modes.map(\.refreshRate).max() ?? 0 }

    public var nativePixels: (width: Int, height: Int)? {
        ModePicker.nativePixelSize(modes)
    }
}
