import AppKit
import ServiceManagement
import UserNotifications
import PulseCore

/// Login item and notifications only work from a real .app bundle. Run from `swift run` they do nothing.
enum LoginItem {
    static var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var status: LoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        default: return .notRegistered
        }
    }

    /// Waiting for approval counts as on: the person asked for it, so the toggle stays on.
    static var enabled: Bool { status.isOn }

    /// Returns a short message when the person needs to do something, nil otherwise.
    static func set(_ on: Bool) -> String? {
        guard available else { return nil }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            return "Couldn't change the login setting."
        }
        if on, SMAppService.mainApp.status == .requiresApproval {
            return "Allow Pulse under Login Items in System Settings."
        }
        return nil
    }
}

enum Notifier {
    static var available: Bool { LoginItem.available }

    /// Asks for permission only the first time a notice is actually due.
    static func post(title: String, body: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        do {
            try await center.add(UNNotificationRequest(identifier: "pulse.needs-you", content: content, trigger: nil))
            return true
        } catch { return false }
    }
}
