import Foundation

enum Areas {
    static func build(_ s: Snapshot, active: [(Fix, String)], freePct: Double?) -> [AreaStatus] {
        func has(_ area: String) -> Bool { active.contains { $0.1 == area } }
        func hasSerious(_ area: String) -> Bool { active.contains { $0.1 == area && $0.0.priority != .warn } }
        var out: [AreaStatus] = []

        // Speed
        var speed: [NumberRow] = []
        if let p = s.memoryPressure {
            speed.append(NumberRow("Memory pressure", p == .normal ? "Normal" : (p == .warning ? "Elevated" : "Critical")))
        }
        if let c = s.totalCPUBusy { speed.append(NumberRow("Processor busy", "\(Int(c.rounded()))%")) }
        if let u = s.uptime { speed.append(NumberRow("Awake for", days(u))) }
        let speedBad = (s.memoryPressure ?? .normal) >= .warning || has("Speed")
        out.append(AreaStatus(
            id: "Speed", symbol: "hare",
            status: speedBad ? "Running slower" : "Running smoothly",
            explain: speedBad ? "Something is using more of your Mac than it should." : "Your apps have the room they need.",
            level: hasSerious("Speed") || s.memoryPressure == .critical ? 0.2 : (speedBad ? 0.5 : 0.9),
            numbers: speed))

        // Heat
        let heatStatus: (String, String, Double) = {
            switch s.thermal {
            case .fair?: return ("Running warm", "A little warm, which is normal under load.", 0.75)
            case .serious?: return ("Running hot", "Your Mac is hot and may slow itself down.", 0.35)
            case .critical?: return ("Too hot", "Your Mac is very hot and is slowing down to cool off.", 0.1)
            default: return ("Running cool", "Your Mac is at a comfortable temperature.", 0.95)
            }
        }()
        var heat: [NumberRow] = []
        if let t = s.thermal {
            heat.append(NumberRow("Thermal state", ["Nominal", "Fair", "Serious", "Critical"][t.rawValue]))
        }
        out.append(AreaStatus(id: "Heat", symbol: "thermometer.medium", status: heatStatus.0,
                              explain: heatStatus.1, level: heatStatus.2, numbers: heat))

        // Storage
        var storage: [NumberRow] = []
        if let f = s.freeBytes { storage.append(NumberRow("Free", gigabytes(f))) }
        if let t = s.totalBytes { storage.append(NumberRow("Total", gigabytes(t))) }
        let full = hasSerious("Storage") || s.diskHealthy == false
        let filling = has("Storage") || (freePct ?? 1) < 0.25
        let stStatus = full ? ("Almost full", "There's very little room left for files and updates.")
            : (filling ? ("Getting full", "There's still space, but it's filling up.")
                       : ("Plenty of room", "There's space for your files and updates."))
        out.append(AreaStatus(id: "Storage", symbol: "externaldrive", status: stStatus.0, explain: stStatus.1,
                              level: full ? 0.1 : min(1, max(0.1, (freePct ?? 0.4) * 2.5)), numbers: storage))

        // Battery (only on Macs that have one)
        if let b = s.battery, b.present {
            var rows: [NumberRow] = []
            if let c = b.maxCapacityPercent { rows.append(NumberRow("Capacity", "\(c)%")) }
            if let c = b.cycleCount { rows.append(NumberRow("Charge cycles", "\(c)")) }
            if let r = b.serviceRecommended { rows.append(NumberRow("Condition", r ? "Service recommended" : "Normal")) }
            let service = b.serviceRecommended == true
            let worn = has("Battery")
            out.append(AreaStatus(
                id: "Battery", symbol: "battery.75percent",
                status: service ? "Needs a service" : (worn ? "Showing its age" : "In good shape"),
                explain: service ? "Apple recommends having it looked at."
                    : (worn ? "It holds less charge than it used to." : "It still holds most of its original charge."),
                level: service ? 0.2 : Double(b.maxCapacityPercent ?? 90) / 100, numbers: rows))
        }

        // Protection
        var prot: [NumberRow] = []
        var issues: [String] = []
        if let v = s.fileVaultOn { prot.append(NumberRow("File encryption", v ? "On" : "Off")); if !v { issues.append("Your files aren't encrypted.") } }
        if let f = s.firewallOn { prot.append(NumberRow("Firewall", f ? "On" : "Off")); if !f { issues.append("The firewall is off.") } }
        if let b = s.lastBackup {
            switch b {
            case .never: prot.append(NumberRow("Last backup", "Never")); issues.append("There's no backup yet.")
            case .date(let d):
                let age = s.date.timeIntervalSince(d)
                prot.append(NumberRow("Last backup", age < 86_400 ? "Today" : "\(Int(age / 86_400)) days ago"))
                if age > 14 * 86_400 { issues.append("Your last backup is old.") }
            }
        }
        if let u = s.updateWaiting { prot.append(NumberRow("Update", u ? "Waiting" : "Up to date")); if u { issues.append("An update is waiting.") } }
        out.append(AreaStatus(
            id: "Protection", symbol: "lock.shield",
            status: issues.isEmpty ? "Well protected" : "Could be safer",
            explain: issues.isEmpty ? "Your files are encrypted and backed up." : issues.joined(separator: " "),
            level: max(0.1, 1 - 0.25 * Double(issues.count)), numbers: prot))
        return out
    }

    static func gigabytes(_ b: UInt64) -> String { "\(Int((Double(b) / 1_000_000_000).rounded())) GB" }

    static func days(_ t: TimeInterval) -> String {
        let d = Int(t / 86_400)
        return d < 1 ? "Under a day" : (d == 1 ? "1 day" : "\(d) days")
    }
}
