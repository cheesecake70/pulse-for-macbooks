import Foundation
import AppKit
import PulseCore
import PulseSystem

func gb(_ b: UInt64?) -> String { b.map { String(format: "%.2f GB", Double($0) / 1e9) } ?? "nil" }
let reader = SystemReader(excludingBundleID: nil)
func show(_ s: Snapshot, _ label: String) {
    print("=== \(label) \(s.date)")
    print("memoryPressure:", s.memoryPressure.map { "\($0)" } ?? "nil")
    print("thermal:", s.thermal.map { "\($0)" } ?? "nil")
    print("totalCPUBusy:", s.totalCPUBusy.map { String(format: "%.1f%%", $0) } ?? "nil")
    print("free/total:", gb(s.freeBytes), "/", gb(s.totalBytes))
    print("diskHealthy:", s.diskHealthy.map { "\($0)" } ?? "nil")
    print("battery:", s.battery.map { "\($0)" } ?? "nil")
    print("uptime(s):", s.uptime.map { String(Int($0)) } ?? "nil")
    print("fileVault:", s.fileVaultOn.map { "\($0)" } ?? "nil", " firewall:", s.firewallOn.map { "\($0)" } ?? "nil")
    print("lastBackup:", s.lastBackup.map { "\($0)" } ?? "nil", " updateWaiting:", s.updateWaiting.map { "\($0)" } ?? "nil")
    print("physicalMemory:", gb(s.physicalMemoryBytes))
    print("apps:")
    for a in (s.apps ?? []).prefix(25) {
        print(String(format: "  %@%-28@ cpu %6.1f%%  mem %8.1f MB  %@", a.isFrontmost ? "*" : " ", a.name as NSString, a.cpuPercent, Double(a.memoryBytes) / 1048576, a.bundleID))
    }
    if s.apps == nil { print("  nil") }
}
let t0 = Date()
show(reader.read(), "read 1 (took \(Int(Date().timeIntervalSince(t0) * 1000)) ms)")
RunLoop.current.run(until: Date().addingTimeInterval(5))
let t1 = Date()
show(reader.read(), "read 2 (took \(Int(Date().timeIntervalSince(t1) * 1000)) ms)")
