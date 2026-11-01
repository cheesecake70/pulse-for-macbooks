import Foundation

/// All the words, in one voice: verb-first titles, lowercase one-line reasons.
enum Copy {
    static func shortName(_ name: String) -> String {
        name.hasPrefix("Google ") ? String(name.dropFirst(7)) : name
    }

    static func quitHeavy(_ app: AppUsage, critical: Bool) -> Fix {
        let n = shortName(app.name)
        return Fix(
            id: "quit.\(app.bundleID)", title: "Quit \(n)",
            reason: "taking up a lot of room.",
            happening: "\(n) is using more of your Mac's memory than anything else.",
            matters: "Other apps slow down and your battery drains faster.",
            willDo: "Asks \(n) to close. It will offer to save anything unsaved.",
            button: "Quit", symbol: "xmark.app", serious: critical, gain: critical ? 20 : 12,
            needsConfirm: true, action: .quitApp(bundleID: app.bundleID, name: app.name))
    }

    static func quitBusy(_ app: AppUsage) -> Fix {
        let n = shortName(app.name)
        return Fix(
            id: "quit.\(app.bundleID)", title: "Quit \(n)",
            reason: "working your mac hard.",
            happening: "\(n) has been using a lot of your Mac for several minutes.",
            matters: "Other apps slow down and your battery drains faster.",
            willDo: "Asks \(n) to close. It will offer to save anything unsaved.",
            button: "Quit", symbol: "xmark.app", serious: false, gain: 12,
            needsConfirm: true, action: .quitApp(bundleID: app.bundleID, name: app.name))
    }

    static func restart(days: Int, serious: Bool) -> Fix {
        Fix(
            id: "restart", title: "Restart your Mac",
            reason: "awake for \(days) days.",
            happening: "Small slowdowns build up when a Mac runs for weeks.",
            matters: "A restart clears them and finishes waiting updates.",
            willDo: "Asks your apps to close, then restarts. Save your work first.",
            button: "Restart", symbol: "arrow.clockwise", serious: serious, gain: serious ? 20 : 12,
            needsConfirm: true, action: .restart)
    }

    static func space(serious: Bool) -> Fix {
        Fix(
            id: "space", title: "Clear some space",
            reason: serious ? "almost out of room." : "getting full.",
            happening: serious ? "Only a small part of your storage is left." : "Your storage is filling up.",
            matters: "With too little room, your Mac slows down and updates can fail.",
            willDo: "Opens Storage in System Settings, where you choose what goes.",
            button: "Open", symbol: "externaldrive", serious: serious, gain: serious ? 20 : 12,
            needsConfirm: false, action: .openSettings(SettingsLink.storage),
            priority: serious ? .dataLoss : .warn)
    }

    static func cool(critical: Bool) -> Fix {
        Fix(
            id: "cool", title: "Let it cool down",
            reason: "running hot.",
            happening: "Your Mac has been very warm for several minutes.",
            matters: "Heat makes it slower and wears the battery.",
            willDo: "Nothing automatic. Move it to a hard, flat surface and keep the vents clear.",
            button: "Got it", symbol: "thermometer.medium", serious: true, gain: 20,
            needsConfirm: false, acknowledgeOnly: true, action: nil, priority: .serious,
            snoozable: !critical)
    }

    static func backups(never: Bool, days: Int) -> Fix {
        Fix(
            id: "backups", title: never ? "Turn on backups" : "Back up your Mac",
            reason: never ? "no backup yet." : "last backup \(days) days ago.",
            happening: never ? "Time Machine hasn't saved a backup." : "Your last backup is getting old.",
            matters: "If your Mac is lost or fails, your files go with it.",
            willDo: "Opens Time Machine in System Settings.",
            button: "Open", symbol: "clock.arrow.circlepath", serious: true, gain: 20,
            needsConfirm: false, action: .openSettings(SettingsLink.timeMachine), priority: .dataLoss)
    }

    static func diskFailing() -> Fix {
        Fix(
            id: "disk", title: "Back up your files now",
            reason: "your drive reports a problem.",
            happening: "Your Mac's drive says it is not healthy.",
            matters: "A failing drive can lose files without warning.",
            willDo: "Opens Time Machine in System Settings so you can back up.",
            button: "Open", symbol: "externaldrive.badge.exclamationmark", serious: true, gain: 24,
            needsConfirm: false, action: .openSettings(SettingsLink.timeMachine), priority: .dataLoss, snoozable: false)
    }

    static func battery(service: Bool) -> Fix {
        Fix(
            id: "battery", title: "Book a battery service",
            reason: service ? "needs a service." : "holds less charge now.",
            happening: service ? "Apple says your battery should be serviced." : "Your battery holds noticeably less than when it was new.",
            matters: "It runs out sooner, and a worn battery can slow your Mac.",
            willDo: "Opens Battery in System Settings, where you can see its condition.",
            button: "Open", symbol: "battery.25percent", serious: false, gain: 12,
            needsConfirm: false, action: .openSettings(SettingsLink.battery))
    }

    static func fileVault() -> Fix {
        Fix(
            id: "filevault", title: "Turn on encryption",
            reason: "your files aren't locked.",
            happening: "FileVault is off, so anyone holding your Mac could read your files.",
            matters: "If your Mac is lost or stolen, your files stay private only with encryption.",
            willDo: "Opens FileVault in System Settings.",
            button: "Open", symbol: "lock.shield", serious: false, gain: 12,
            needsConfirm: false, action: .openSettings(SettingsLink.fileVault))
    }

    static func firewall() -> Fix {
        Fix(
            id: "firewall", title: "Turn on the firewall",
            reason: "the firewall is off.",
            happening: "Nothing is checking connections coming into your Mac.",
            matters: "On shared networks, other devices can reach your apps more easily.",
            willDo: "Opens Network settings, where the firewall lives.",
            button: "Open", symbol: "flame", serious: false, gain: 12,
            needsConfirm: false, action: .openSettings(SettingsLink.firewall))
    }

    static func update() -> Fix {
        Fix(
            id: "update", title: "Install the update",
            reason: "an update is waiting.",
            happening: "A macOS update is ready to install.",
            matters: "Updates carry security fixes and keep your apps working.",
            willDo: "Opens Software Update in System Settings.",
            button: "Open", symbol: "square.and.arrow.down", serious: false, gain: 12,
            needsConfirm: false, action: .openSettings(SettingsLink.softwareUpdate))
    }
}
