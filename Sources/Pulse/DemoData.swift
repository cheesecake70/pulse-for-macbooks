import SwiftUI
import PulseCore

// Made-up data for `--demo` and the design snapshots. Nothing here reads or changes the Mac.

enum Scenario: String, CaseIterable, Identifiable {
    case healthy = "Healthy"
    case better = "Could be better"
    case attention = "Needs attention"
    var id: String { rawValue }
}

enum Route: Hashable {
    case home, details, habits, settings
    case area(String)
}

struct Area: Identifiable {
    let id: String
    let symbol: String
    let status: String
    let explain: String
    let level: Double
    let numbers: [(String, String)]

    init(id: String, symbol: String, status: String, explain: String, level: Double, numbers: [(String, String)]) {
        self.id = id; self.symbol = symbol; self.status = status
        self.explain = explain; self.level = level; self.numbers = numbers
    }

    init(_ a: AreaStatus) {
        self.init(id: a.id, symbol: a.symbol, status: a.status, explain: a.explain, level: a.level,
                  numbers: a.numbers.map { ($0.label, $0.value) })
    }
}

enum Demo {
    static let chrome = Fix(
        id: "chrome", title: "Quit Chrome",
        reason: "working your mac hard.",
        happening: "Chrome is using more of your Mac than everything else put together.",
        matters: "Other apps slow down and your battery drains faster.",
        willDo: "Asks Chrome to close. It will offer to save anything unsaved.",
        button: "Quit", symbol: "xmark.app", serious: false, gain: 9, needsConfirm: true)
    static let restart = Fix(
        id: "restart", title: "Restart your Mac",
        reason: "awake for 21 days.",
        happening: "Small slowdowns build up when a Mac runs for weeks.",
        matters: "A restart clears them and finishes waiting updates.",
        willDo: "Asks your apps to close, then restarts. Save your work first.",
        button: "Restart", symbol: "arrow.clockwise", serious: false, gain: 7, needsConfirm: true)
    static let space = Fix(
        id: "space", title: "Clear some space",
        reason: "almost out of room.",
        happening: "Only a small part of your storage is left.",
        matters: "With too little room, your Mac slows down and updates can fail.",
        willDo: "Opens Storage in System Settings, where you choose what goes.",
        button: "Open", symbol: "externaldrive", serious: true, gain: 16, needsConfirm: false)
    static let cool = Fix(
        id: "cool", title: "Let it cool down",
        reason: "running hot.",
        happening: "Your Mac has been very warm for several minutes.",
        matters: "Heat makes it slower and wears the battery.",
        willDo: "Nothing automatic. Move it to a hard, flat surface and keep the vents clear.",
        button: "Got it", symbol: "thermometer.medium", serious: true, gain: 12, needsConfirm: false, acknowledgeOnly: true)
    static let backups = Fix(
        id: "backups", title: "Turn on backups",
        reason: "no backup yet.",
        happening: "Time Machine hasn't saved a backup.",
        matters: "If your Mac is lost or fails, your files go with it.",
        willDo: "Opens Time Machine in System Settings.",
        button: "Open", symbol: "clock.arrow.circlepath", serious: true, gain: 12, needsConfirm: false)

    static let areas: [Area] = [
        Area(id: "Speed", symbol: "hare", status: "Running smoothly",
             explain: "Your apps have the room they need.", level: 0.9,
             numbers: [("Memory pressure", "Normal"), ("Processor busy", "14%"), ("Awake for", "3 days")]),
        Area(id: "Heat", symbol: "thermometer.medium", status: "Running cool",
             explain: "Your Mac is at a comfortable temperature.", level: 0.95,
             numbers: [("Thermal state", "Nominal")]),
        Area(id: "Storage", symbol: "externaldrive", status: "Plenty of room",
             explain: "There's space for your files and updates.", level: 0.72,
             numbers: [("Free", "142 GB"), ("Total", "494 GB")]),
        Area(id: "Battery", symbol: "battery.75percent", status: "In good shape",
             explain: "It still holds most of its original charge.", level: 0.88,
             numbers: [("Capacity", "88%"), ("Charge cycles", "312"), ("Condition", "Normal")]),
        Area(id: "Protection", symbol: "lock.shield", status: "Well protected",
             explain: "Your files are encrypted and backed up.", level: 1,
             numbers: [("File encryption", "On"), ("Firewall", "On"), ("Last backup", "Today")]),
    ]

    static let habits: [(String, String, String)] = [
        ("arrow.clockwise", "Restart about once a week", "It clears small slowdowns."),
        ("externaldrive", "Keep some storage free", "Aim for about 15 to 20 percent."),
        ("square.and.arrow.down", "Install updates", "They carry security fixes."),
        ("clock.arrow.circlepath", "Keep a backup", "It protects what you can't replace."),
        ("wind", "Use a hard, flat surface", "Beds and laps block the vents."),
        ("sun.max", "Avoid heat", "Keep it out of sun and hot cars."),
        ("battery.75percent", "Leave Optimised Charging on", "Staying plugged in is fine."),
        ("macwindow.on.rectangle", "Close tabs you aren't using", "Each one takes a little room."),
        ("leaf", "Use Low Power Mode away from power", "Your charge lasts longer."),
    ]
}
