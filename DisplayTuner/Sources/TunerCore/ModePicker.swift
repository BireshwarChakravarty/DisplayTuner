import Foundation

/// Chooses desktop sizes and refresh rates from the modes a display offers.
public enum ModePicker {
    /// macOS's interface is drawn for roughly 110 points per inch (and twice
    /// that in pixels on HiDPI). Sizes near it look like a Mac should.
    public static let idealPointsPerInch = 110.0

    public enum RefreshPolicy: Sendable {
        /// The fastest rate available.
        case highest
        /// A rate that divides evenly by 24, 25 or 30 fps footage, preferring
        /// one that fits both 24 and 30 (120 Hz), so playback has no judder.
        case videoFriendly
    }

    /// The panel's native resolution: the largest non-HiDPI framebuffer.
    public static func nativePixelSize(_ modes: [DisplayMode]) -> (width: Int, height: Int)? {
        let plain = modes.filter { !$0.isHiDPI }
        let pool = plain.isEmpty ? modes : plain
        guard let best = pool.max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }) else { return nil }
        return (best.pixelWidth, best.pixelHeight)
    }

    /// Layouts that render sharply: the native resolution, and HiDPI layouts
    /// drawn at or above native resolution. (Non-native, non-HiDPI sizes are
    /// upscaled by the monitor and look soft.)
    public static func sharpLayouts(_ modes: [DisplayMode]) -> [Layout] {
        guard let native = nativePixelSize(modes) else { return [] }
        let layouts = Set(modes.filter(\.usableForDesktop).map(\.layout)).filter { layout in
            if layout.isHiDPI { return layout.pixelWidth >= native.width }
            return layout.pixelWidth == native.width && layout.pixelHeight == native.height
        }
        return layouts.sorted { $0.width * $0.height < $1.width * $1.height }
    }

    public static func isSharp(_ layout: Layout, in modes: [DisplayMode]) -> Bool {
        sharpLayouts(modes).contains(layout)
    }

    /// The sharp layout whose density is closest to the macOS ideal. Without a
    /// physical size, prefer exact 2× HiDPI, then native.
    public static func recommendedLayout(_ modes: [DisplayMode], widthMM: Double?) -> Layout? {
        let candidates = sharpLayouts(modes)
        guard !candidates.isEmpty, let native = nativePixelSize(modes) else { return nil }
        if let mm = widthMM, mm > 50 {
            let inches = mm / 25.4
            return candidates.min { a, b in
                let da = abs(Double(a.width) / inches - idealPointsPerInch)
                let db = abs(Double(b.width) / inches - idealPointsPerInch)
                if abs(da - db) < 0.5 { return a.isHiDPI && !b.isHiDPI } // tie: prefer HiDPI
                return da < db
            }
        }
        return candidates.first { $0.isHiDPI && $0.pixelWidth == native.width }
            ?? candidates.first { !$0.isHiDPI }
            ?? candidates.first
    }

    public static func pointsPerInch(_ layout: Layout, widthMM: Double?) -> Double? {
        guard let mm = widthMM, mm > 50 else { return nil }
        return Double(layout.width) / (mm / 25.4)
    }

    /// The best mode for `layout` under `policy`.
    public static func bestMode(for layout: Layout, in modes: [DisplayMode], policy: RefreshPolicy) -> DisplayMode? {
        let options = modes.filter { $0.layout == layout && $0.usableForDesktop }
        guard let fastest = options.max(by: { $0.refreshRate < $1.refreshRate }) else { return nil }
        switch policy {
        case .highest:
            return fastest
        case .videoFriendly:
            func fits(_ mode: DisplayMode, _ rates: [Double]) -> Bool {
                let hz = mode.refreshRate.rounded()
                return hz > 0 && rates.allSatisfy { hz.truncatingRemainder(dividingBy: $0) == 0 }
            }
            let both = options.filter { fits($0, [24, 30]) }.max { $0.refreshRate < $1.refreshRate }
            let film = options.filter { fits($0, [24]) }.max { $0.refreshRate < $1.refreshRate }
            return both ?? film ?? fastest
        }
    }

    /// A lower-resolution mode that runs faster than anything at native
    /// resolution, e.g. a dual-mode monitor's 1080p @ 320 Hz.
    public static func fastLowResolutionMode(_ modes: [DisplayMode]) -> DisplayMode? {
        guard let native = nativePixelSize(modes) else { return nil }
        let nativeTop = modes.filter { $0.pixelWidth >= native.width }.map(\.refreshRate).max() ?? 0
        return modes
            .filter { $0.usableForDesktop && $0.refreshRate > nativeTop + 1 }
            .max { ($0.refreshRate, $0.pixelWidth) < ($1.refreshRate, $1.pixelWidth) }
    }

    /// Modes worth offering in a picker: every sharp layout at each of its
    /// refresh rates, plus any faster low-resolution mode. Fastest first.
    public static func menuModes(_ modes: [DisplayMode]) -> [DisplayMode] {
        let sharp = Set(sharpLayouts(modes))
        var seen = Set<String>()
        var result: [DisplayMode] = []
        let sorted = modes
            .filter { $0.usableForDesktop && sharp.contains($0.layout) }
            .sorted { ($0.width * $0.height, $0.refreshRate) < ($1.width * $1.height, $1.refreshRate) }
        for mode in sorted {
            let key = "\(mode.layout.label)@\(Int(mode.refreshRate.rounded()))"
            if seen.insert(key).inserted { result.append(mode) }
        }
        if let fast = fastLowResolutionMode(modes) { result.append(fast) }
        return result
    }
}
