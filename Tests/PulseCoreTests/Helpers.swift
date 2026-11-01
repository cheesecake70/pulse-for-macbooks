import Foundation
@testable import PulseCore

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
let GB: UInt64 = 1_000_000_000

func app(_ name: String, cpu: Double = 5, gb: Double = 0.5, front: Bool = false, id: String? = nil) -> AppUsage {
    AppUsage(name: name, bundleID: id ?? "com.test.\(name)", cpuPercent: cpu,
             memoryBytes: UInt64(gb * Double(GB)), isFrontmost: front)
}

/// A calm, fully known Mac. Tests change one thing at a time.
func calm(_ at: Date, apps: [AppUsage]? = nil) -> Snapshot {
    Snapshot(date: at, memoryPressure: .normal, thermal: .nominal,
             apps: apps ?? [app("Chrome", cpu: 30, gb: 2, front: true), app("Mail")],
             totalCPUBusy: 15, freeBytes: 200 * GB, totalBytes: 500 * GB, diskHealthy: true,
             battery: BatteryReading(present: true, cycleCount: 100, maxCapacityPercent: 95, serviceRecommended: false),
             uptime: 2 * 86_400, fileVaultOn: true, firewallOn: true,
             lastBackup: .date(at.addingTimeInterval(-3600)), updateWaiting: false,
             physicalMemoryBytes: 8 * GB)
}

func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

/// Feeds the same snapshot-maker once per `step` seconds and returns the last report.
@discardableResult
func run(_ engine: inout HealthEngine, minutes: Double, step: Double = 30,
         from start: Double = 0, _ make: (Date) -> Snapshot) -> Report {
    var r: Report?
    var t = 0.0
    while t <= minutes * 60 {
        r = engine.ingest(make(t0.addingTimeInterval(start * 60 + t)))
        t += step
    }
    return r!
}
