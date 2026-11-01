import Foundation

/// What a fix does when the person taps its button. A closed set, so nothing else can ever exist.
public enum FixAction: Sendable, Equatable {
    case quitApp(bundleID: String, name: String)
    case restart
    case openSettings(String)
    case relaunch(app: String)

    /// Two fixes with the same key are the same action and get merged.
    var key: String {
        switch self {
        case .quitApp(let id, _): return "quit:\(id)"
        case .restart: return "restart"
        case .openSettings(let url): return "open:\(url)"
        case .relaunch(let app): return "relaunch:\(app)"
        }
    }
}

public enum FixPriority: Int, Sendable, Comparable {
    case warn, serious, dataLoss
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct Fix: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let reason: String
    public let happening: String
    public let matters: String
    public let willDo: String
    public let button: String
    public let symbol: String
    public let serious: Bool
    public let gain: Int
    /// Quit and restart ask first; opening a Settings page doesn't.
    public let needsConfirm: Bool
    /// Acknowledging doesn't fix anything; the row stays until the Mac recovers.
    public var acknowledgeOnly: Bool
    public let action: FixAction?
    public let priority: FixPriority
    /// False for things that must never be hidden (a failing disk, critical heat).
    public let snoozable: Bool

    public init(id: String, title: String, reason: String, happening: String, matters: String,
                willDo: String, button: String, symbol: String, serious: Bool, gain: Int,
                needsConfirm: Bool, acknowledgeOnly: Bool = false,
                action: FixAction? = nil, priority: FixPriority? = nil, snoozable: Bool = true) {
        self.id = id; self.title = title; self.reason = reason; self.happening = happening
        self.matters = matters; self.willDo = willDo; self.button = button; self.symbol = symbol
        self.serious = serious; self.gain = gain; self.needsConfirm = needsConfirm
        self.acknowledgeOnly = acknowledgeOnly; self.action = action
        self.priority = priority ?? (serious ? .serious : .warn)
        self.snoozable = snoozable
    }
}

/// Every Settings link in one place, so they can be corrected after testing on a real Mac.
public enum SettingsLink {
    public static let storage = "x-apple.systempreferences:com.apple.settings.Storage"
    public static let fileVault = "x-apple.systempreferences:com.apple.preference.security?FileVault"
    public static let firewall = "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
    public static let timeMachine = "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"
    public static let softwareUpdate = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    public static let battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
}
