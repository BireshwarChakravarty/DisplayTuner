import AppKit
import ColorSync
import CoreGraphics
import TunerCore

/// Reads what macOS knows about each connected display.
enum DisplayDetector {
    static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    /// Detects every display. DDC status is filled in separately (it's slow).
    @MainActor
    static func detect(nameFallback: (CGDirectDisplayID) -> String?) -> [DisplayFacts] {
        onlineDisplayIDs().map { id in
            let screen = screen(for: id)
            let mirror = CGDisplayMirrorsDisplay(id)
            let size = CGDisplayScreenSize(id)

            let colorSpace = CGDisplayCopyColorSpace(id)
            let icc = colorSpace.copyICCData() as Data?
            let customProfile = ColorProfiles.customProfileURL(for: id)
            // The panel's gamut comes from its own (factory) profile; the active
            // one may be an assigned sRGB profile that says nothing about the panel.
            let panelICC = ColorProfiles.factoryProfileData(for: id) ?? (customProfile == nil ? icc : nil)

            var name = screen?.localizedName ?? nameFallback(id) ?? "Display \(id)"
            if CGDisplayIsBuiltin(id) != 0, screen == nil { name = "Built-in Display" }

            return DisplayFacts(
                id: id,
                name: name,
                vendorID: CGDisplayVendorNumber(id),
                productID: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                mirrorOf: mirror == kCGNullDirectDisplay ? nil : mirror,
                modes: DisplayModes.all(for: id).map(DisplayModes.model),
                currentMode: CGDisplayCopyDisplayMode(id).map(DisplayModes.model),
                widthMM: size.width > 0 ? Double(size.width) : nil,
                primaries: panelICC.flatMap(ICCProfile.primaries(from:)),
                profileName: icc.flatMap(ICCProfile.description(from:)) ?? (colorSpace.name as String?),
                customProfilePath: customProfile?.path,
                edrHeadroom: Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1),
                ddc: CGDisplayIsBuiltin(id) != 0 ? .unavailable : .unknown,
                persistentID: owned(CGDisplayCreateUUIDFromDisplayID(id)).map { CFUUIDCreateString(nil, $0) as String })
        }
    }
}

/// Resolution and refresh rate.
enum DisplayModes {
    static func all(for id: CGDirectDisplayID) -> [CGDisplayMode] {
        // Include the HiDPI ("looks like") variants System Settings shows.
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
    }

    static func model(_ mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(
            modeID: mode.ioDisplayModeID,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            usableForDesktop: mode.isUsableForDesktopGUI())
    }

    /// Switch a display to `mode`. `permanent` keeps it across restarts, like
    /// System Settings; otherwise it lasts for this login session only, so an
    /// unconfirmed change can't outlive a crash or restart.
    static func apply(_ mode: DisplayMode, to id: CGDirectDisplayID, permanent: Bool = true) -> Bool {
        let candidates = all(for: id)
        guard let target = candidates.first(where: { $0.ioDisplayModeID == mode.modeID && model($0).matches(mode) })
                ?? candidates.first(where: { model($0).matches(mode) }) else {
            Log.display.error("No mode \(mode.label, privacy: .public) on display \(id)")
            return false
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, id, target, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, permanent ? .permanently : .forSession) == .success
    }
}

// MARK: - ColorSync

// ColorSync's constants and copy functions come into Swift either as plain CF
// types or as Unmanaged, depending on the SDK; these overloads accept both.
private func cf(_ value: CFString) -> CFString { value }
private func cf(_ value: Unmanaged<CFString>) -> CFString { value.takeUnretainedValue() }
private func owned<T: AnyObject>(_ value: Unmanaged<T>?) -> T? { value?.takeRetainedValue() }
private func owned<T: AnyObject>(_ value: T?) -> T? { value }

/// Which ICC profile macOS uses for each display (System Settings → Displays → Color profile).
enum ColorProfiles {
    static let systemDirectory = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles")

    private static var displayClass: CFString { cf(kColorSyncDisplayDeviceClass) }
    private static var defaultProfileKey: String { cf(kColorSyncDeviceDefaultProfileID) as String }

    private static func deviceID(_ id: CGDirectDisplayID) -> CFUUID? {
        owned(CGDisplayCreateUUIDFromDisplayID(id))
    }

    private static func deviceInfo(_ id: CGDirectDisplayID) -> NSDictionary? {
        guard let uuid = deviceID(id) else { return nil }
        let info: CFDictionary? = owned(ColorSyncDeviceCopyDeviceInfo(displayClass, uuid))
        return info as NSDictionary?
    }

    /// The profile someone assigned to this display, or nil if it uses its
    /// own (factory / EDID) profile.
    ///
    /// ColorSyncDevice.h: the default profile's ID sits inside the
    /// kColorSyncFactoryProfiles dictionary; kColorSyncCustomProfiles maps
    /// that ID to a URL, or to kCFNull when no profile was assigned.
    static func customProfileURL(for id: CGDirectDisplayID) -> URL? {
        guard let info = deviceInfo(id),
              let custom = info[cf(kColorSyncCustomProfiles) as String] as? NSDictionary else { return nil }
        let value = defaultProfileID(info).flatMap { custom[$0] } ?? custom[defaultProfileKey]
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        return nil
    }

    /// The ICC data of the display's own profile, from its factory entry.
    static func factoryProfileData(for id: CGDirectDisplayID) -> Data? {
        guard let info = deviceInfo(id), let profileID = defaultProfileID(info),
              let factory = info[cf(kColorSyncFactoryProfiles) as String] as? NSDictionary,
              let entry = factory[profileID] as? NSDictionary else { return nil }
        let value = entry[cf(kColorSyncDeviceProfileURL) as String]
        guard let url = (value as? URL) ?? (value as? NSURL).map({ $0 as URL }) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func defaultProfileID(_ info: NSDictionary) -> String? {
        (info[cf(kColorSyncFactoryProfiles) as String] as? NSDictionary)?[defaultProfileKey] as? String
    }

    static func url(for choice: ProfileChoice) -> URL? {
        switch choice {
        case .factory: return nil
        case .system(let file):
            let url = systemDirectory.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// Assign `url` to the display, or go back to its own profile with nil.
    static func setProfile(_ url: URL?, for id: CGDirectDisplayID) -> Bool {
        guard let uuid = deviceID(id) else { return false }
        let info = NSMutableDictionary()
        if let url {
            info[defaultProfileKey] = url as NSURL
        } else {
            info[defaultProfileKey] = kCFNull // back to the factory profile
        }
        info[cf(kColorSyncProfileUserScope) as String] = kCFPreferencesCurrentUser
        let ok = ColorSyncDeviceSetCustomProfiles(displayClass, uuid, info as CFDictionary)
        Log.display.info("Set colour profile \(url?.lastPathComponent ?? "factory", privacy: .public) on \(id): \(ok)")
        return ok
    }
}

// MARK: - Night Shift

/// Night Shift through CoreBrightness's CBBlueLightClient. It's a private
/// framework, so every call checks the class and method exist first and the
/// feature just disappears if they don't.
final class NightShift {
    private let client: NSObject?

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        if let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
            client = type.init()
        } else {
            client = nil
        }
    }

    /// Whether Night Shift is on right now, or nil if it can't be read.
    func isEnabled() -> Bool? {
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard let client, client.responds(to: selector), let imp = client.method(for: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let get = unsafeBitCast(imp, to: Getter.self)
        // struct { BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode; ... }
        // padded generously.
        var status = [UInt8](repeating: 0, count: 128)
        let ok = status.withUnsafeMutableBytes { get(client, selector, $0.baseAddress!) }
        return ok ? status[1] != 0 : nil
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        let selector = NSSelectorFromString("setEnabled:")
        guard let client, client.responds(to: selector), let imp = client.method(for: selector) else { return false }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let set = unsafeBitCast(imp, to: Setter.self)
        return set(client, selector, enabled)
    }
}
