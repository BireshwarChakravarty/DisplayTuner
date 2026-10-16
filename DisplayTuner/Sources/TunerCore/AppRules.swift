import Foundation

/// Which preset an app in front should use, for automatic switching.
///
/// Games are recognised by the App Store category every game declares
/// (`LSApplicationCategoryType`, e.g. `public.app-category.action-games`) or by
/// living in a Steam library. Editors are recognised by bundle identifier.
public enum AppRules {
    /// Bundle identifier prefixes of photo editors.
    public static let photoEditors = [
        "com.adobe.Photoshop", "com.adobe.LightroomClassicCC", "com.adobe.lightroomCC", "com.adobe.Lightroom",
        "com.captureone.", "com.phaseone.captureone", "com.seriflabs.affinityphoto",
        "com.pixelmatorteam.pixelmator", "com.dxo.", "com.skylum.", "org.darktable", "com.apple.Aperture"
    ]

    /// Bundle identifier prefixes of video editors and grading tools.
    public static let videoEditors = [
        "com.apple.FinalCut", "com.apple.motionapp", "com.blackmagic-design.DaVinciResolve",
        "com.adobe.PremierePro", "com.adobe.AfterEffects", "com.adobe.Premiere"
    ]

    public static func isGame(category: String?, path: String?) -> Bool {
        if let category = category?.lowercased(), category.hasPrefix("public.app-category."), category.hasSuffix("games") {
            return true
        }
        if let path = path?.lowercased(), path.contains("/steamapps/common/") { return true }
        return false
    }

    /// The preset for an app, or nil if it has none (the person's own preset applies).
    public static func useCase(bundleID: String?, category: String?, path: String?, gamePreset: UseCase) -> UseCase? {
        if let id = bundleID {
            if photoEditors.contains(where: { id.hasPrefix($0) }) { return .photoEditing }
            if videoEditors.contains(where: { id.hasPrefix($0) }) { return .videoEditing }
        }
        return isGame(category: category, path: path) ? gamePreset : nil
    }
}
