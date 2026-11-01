import Foundation

/// The one source of truth for which apps may ever be quit. The engine only suggests apps that pass,
/// and the action runner refuses everything that fails.
public enum QuitPolicy {
    public static let ownBundleID = "com.mokssha.pulse"
    public static let neverQuit: Set<String> = [
        ownBundleID, "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.loginwindow", "com.apple.WindowManager", "com.apple.controlcenter",
        "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.coreservices.uiagent",
        "com.apple.SystemUIServer", "com.apple.systempreferences", "com.apple.Terminal",
    ]

    /// Apple apps people use directly and may reasonably quit.
    public static let userFacingApple: Set<String> = [
        "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.iCal", "com.apple.Music",
        "com.apple.TV", "com.apple.Photos", "com.apple.Preview", "com.apple.TextEdit",
        "com.apple.Maps", "com.apple.MobileSMS", "com.apple.FaceTime", "com.apple.reminders",
        "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
        "com.apple.Podcasts", "com.apple.news", "com.apple.AddressBook", "com.apple.freeform",
    ]

    /// nil means allowed.
    public static func refusal(bundleID: String) -> String? {
        if bundleID.isEmpty || bundleID.count > 200 || bundleID.hasPrefix("pid.") {
            return "That app can't be identified."
        }
        if neverQuit.contains(bundleID) { return "This is part of macOS and can't be quit from here." }
        if bundleID.lowercased().hasPrefix("com.apple.") && !userFacingApple.contains(bundleID) {
            return "This is part of macOS and can't be quit from here."
        }
        return nil
    }

    public static func isQuittable(_ bundleID: String) -> Bool { refusal(bundleID: bundleID) == nil }
}

/// Snooze lengths and words, in one place.
public enum SnoozeCopy {
    static let day: TimeInterval = 86_400
    public static func length(for fixID: String) -> TimeInterval { fixID == "battery" ? 30 * day : day }
    public static func button(for fixID: String) -> String {
        fixID == "battery" ? "Hide for 30 days" : "Hide until tomorrow"
    }
    public static func toast(for fixID: String) -> String {
        fixID == "battery" ? "Hidden for 30 days" : "Hidden until tomorrow"
    }
}

/// Login item states, so "waiting for approval" counts as on and the toggle is not flipped off.
public enum LoginStatus: Sendable {
    case notRegistered, enabled, requiresApproval, notFound
    public var isOn: Bool { self == .enabled || self == .requiresApproval }
}
