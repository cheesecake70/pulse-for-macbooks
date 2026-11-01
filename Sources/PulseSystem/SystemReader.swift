import Foundation
import AppKit
import Darwin
import IOKit
import PulseCore

/// Gathers one `Snapshot` of the Mac. Safe to call from any background queue (calls are serialised).
/// Every individual reading is nil when it cannot be read; it never throws and never prompts.
public final class SystemReader: @unchecked Sendable {
    private let lock = NSLock()
    private let excludedBundleID: String?
    private let ownPID = getpid()

    // CPU delta state
    private var prevProcTimes: [Int32: UInt64] = [:]   // pid -> cpu ns
    private var prevProcWall: UInt64?                  // mach ns
    private var prevCPUTicks: (busy: UInt64, total: UInt64)?
    private let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t
    }()

    private let diskHealth = TimedCache<Bool>(ttl: 6 * 3600)
    private let batteryExtra = TimedCache<Bool>(ttl: 6 * 3600)
    private let fileVault = TimedCache<Bool>(ttl: 3600)
    private let firewall = TimedCache<Bool>(ttl: 3600)
    private let backup = TimedCache<BackupState>(ttl: 3600)

    /// - Parameter excludingBundleID: the host app's bundle id, left out of the per-app list (defaults to the main bundle).
    public init(excludingBundleID: String? = Bundle.main.bundleIdentifier) {
        self.excludedBundleID = excludingBundleID
    }

    /// Reads everything. The first call has `totalCPUBusy == nil` and every app's `cpuPercent == 0` (no earlier sample to diff against).
    /// - Parameter includeApps: pass false to skip the per-app scan (the process walk is the only moderately costly step).
    /// - Parameter allowSpawn: pass false to reuse cached values instead of launching helper commands, even when they have expired.
    /// - Parameter runningApps: apps captured on the main thread (NSWorkspace only refreshes with the main run loop); nil asks NSWorkspace here.
    /// - Parameter frontmostPID: the frontmost app's pid, captured alongside `runningApps`.
    public func read(includeApps: Bool = true, allowSpawn: Bool = true,
                     runningApps: [NSRunningApplication]? = nil, frontmostPID: Int32? = nil) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        var s = Snapshot(date: now)
        s.memoryPressure = readMemoryPressure()
        s.thermal = readThermal()
        s.totalCPUBusy = readTotalCPU()
        if includeApps { s.apps = readApps(running: runningApps, givenFront: frontmostPID) }
        let st = readStorage()
        s.freeBytes = st?.free
        s.totalBytes = st?.total
        s.diskHealthy = diskHealth.get(now: now, allowProduce: allowSpawn) { Self.readDiskHealth() }
        s.battery = readBattery(now: now, allowSpawn: allowSpawn)
        if let b = Sys.bootDate() { s.uptime = max(0, now.timeIntervalSince(b)) }
        s.fileVaultOn = fileVault.get(now: now, allowProduce: allowSpawn) { Self.readFileVault() }
        s.firewallOn = firewall.get(now: now, allowProduce: allowSpawn) { Self.readFirewall() }
        s.lastBackup = backup.get(now: now, allowProduce: allowSpawn) { Self.readBackup() }
        s.updateWaiting = Self.readUpdateWaiting()
        s.physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        return s
    }

    // MARK: simple readers

    func readMemoryPressure() -> MemoryPressure? {
        switch Sys.sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return nil
        }
    }

    func readThermal() -> ThermalLevel? {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return nil
        }
    }

    private func readTotalCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let user = UInt64(t.0), sys = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        let total = user + sys + idle + nice
        let busy = user + sys + nice
        defer { prevCPUTicks = (busy, total) }
        guard let p = prevCPUTicks, total > p.total else { return nil }
        return min(100, max(0, Double(busy - p.busy) / Double(total - p.total) * 100))
    }

    private func readStorage() -> (free: UInt64, total: UInt64)? {
        // The home directory lives on the Data volume, which is the one the owner sees as "free space".
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity, total > 0
        else { return nil }
        return (UInt64(max(0, free)), UInt64(total))
    }

    // MARK: disk health

    static func readDiskHealth() -> Bool? {
        guard let r = Sys.run("/usr/sbin/diskutil", ["info", "/"]) else { return nil }
        for line in r.output.split(separator: "\n") {
            guard let range = line.range(of: "SMART Status:") else { continue }
            let v = line[range.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            if v.hasPrefix("verified") { return true }
            if v.hasPrefix("failing") || v.hasPrefix("about to fail") { return false }
            return nil   // "Not Supported" and anything else
        }
        return nil
    }

    // MARK: battery

    private func readBattery(now: Date, allowSpawn: Bool = true) -> BatteryReading? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return BatteryReading(present: false) }
        defer { IOObjectRelease(svc) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return BatteryReading(present: true)
        }
        func int(_ k: String) -> Int? { (props[k] as? NSNumber)?.intValue }
        if let installed = props["BatteryInstalled"] as? Bool, !installed { return BatteryReading(present: false) }

        let cycles = int("CycleCount")
        var percent: Int?
        // On Apple Silicon "MaxCapacity" is a 0-100 gauge, so use NominalChargeCapacity (what System Settings reports)
        // or AppleRawMaxCapacity, both in mAh, against DesignCapacity.
        if let design = int("DesignCapacity"), design > 1000 {
            if let cap = int("NominalChargeCapacity"), cap > 0 {
                percent = Int((Double(cap) / Double(design) * 100).rounded())
            } else if let cap = int("AppleRawMaxCapacity"), cap > 0 {
                percent = Int((Double(cap) / Double(design) * 100).rounded())
            }
        }
        if let p = percent { percent = min(100, max(0, p)) }

        var service: Bool?
        if let pf = int("PermanentFailureStatus"), pf != 0 {
            service = true
        } else {
            service = batteryExtra.get(now: now, allowProduce: allowSpawn) { Self.readBatteryServiceRecommended() }
        }
        return BatteryReading(present: true, cycleCount: cycles, maxCapacityPercent: percent, serviceRecommended: service)
    }

    static func readBatteryServiceRecommended() -> Bool? {
        guard let r = Sys.run("/usr/sbin/system_profiler", ["SPPowerDataType"], timeout: 5) else { return nil }
        for line in r.output.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Condition:") {
                let v = t.dropFirst("Condition:".count).trimmingCharacters(in: .whitespaces).lowercased()
                if v == "normal" { return false }
                if v.contains("service") || v.contains("replace") || v.contains("poor") { return true }
                return nil
            }
        }
        return nil
    }

    // MARK: protection

    static func readFileVault() -> Bool? {
        guard let r = Sys.run("/usr/bin/fdesetup", ["status"]) else { return nil }
        let o = r.output.lowercased()
        if o.contains("filevault is on") { return true }
        if o.contains("filevault is off") { return false }
        return nil
    }

    static func readFirewall() -> Bool? {
        guard let r = Sys.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]) else { return nil }
        let o = r.output.lowercased()
        if o.contains("enabled") { return true }
        if o.contains("disabled") { return false }
        return nil
    }

    /// Prefers the Time Machine preferences file (world-readable, no subprocess); falls back to `tmutil`.
    static func readBackup() -> BackupState? {
        if let prefs = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.TimeMachine.plist") {
            if let dests = prefs["Destinations"] as? [[String: Any]], !dests.isEmpty {
                var newest: Date?
                for d in dests {
                    for case let date as Date in (d["SnapshotDates"] as? [Any] ?? []) {
                        if newest == nil || date > newest! { newest = date }
                    }
                }
                if let n = newest { return .date(n) }
            }
        }
        if let r = Sys.run("/usr/bin/tmutil", ["latestbackup"]), r.status == 0,
           let name = r.output.split(separator: "\n").first.map({ ($0 as Substring).split(separator: "/").last.map(String.init) ?? "" }),
           let d = parseBackupName(name) {
            return .date(d)
        }
        // No date found. "Never" only if there is positively no destination configured.
        if let r = Sys.run("/usr/bin/tmutil", ["destinationinfo"]) {
            let o = r.output.lowercased()
            if o.contains("no destinations configured") { return BackupState.never }
        }
        return nil
    }

    static func parseBackupName(_ name: String) -> Date? {
        let base = name.replacingOccurrences(of: ".backup", with: "").replacingOccurrences(of: ".inProgress", with: "")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.date(from: base)
    }

    /// Reads the world-readable SoftwareUpdate plist directly; nil if it cannot be read.
    static func readUpdateWaiting() -> Bool? {
        guard let d = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist") else { return nil }
        if let n = (d["LastRecommendedUpdatesAvailable"] as? NSNumber)?.intValue { return n > 0 }
        if let arr = d["RecommendedUpdates"] as? [Any] { return !arr.isEmpty }
        return false
    }

    // MARK: per-app usage

    private func nanos(_ machTime: UInt64) -> UInt64 {
        // Apple Silicon ticks are not nanoseconds (numer/denom = 125/3); convert via the timebase.
        machTime / UInt64(timebase.denom) * UInt64(timebase.numer)
            + (machTime % UInt64(timebase.denom)) * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private struct Proc { var ppid: Int32; var uid: UInt32 }

    private func readApps(running: [NSRunningApplication]?, givenFront: Int32?) -> [AppUsage]? {
        let ws = NSWorkspace.shared
        let regular = (running ?? ws.runningApplications).filter { $0.activationPolicy == .regular && $0.processIdentifier > 0 }
        guard !regular.isEmpty else { return nil }
        var appByPID: [Int32: NSRunningApplication] = [:]
        for a in regular { appByPID[a.processIdentifier] = a }
        let frontPID = running != nil ? givenFront : ws.frontmostApplication?.processIdentifier
        let bundlePaths: [(prefix: String, pid: Int32)] = regular.compactMap {
            guard let p = $0.bundleURL?.path else { return nil }
            return (p.hasSuffix("/") ? p : p + "/", $0.processIdentifier)
        }.sorted { $0.prefix.count > $1.prefix.count }

        // All pids
        var pids = [Int32](repeating: 0, count: 4096)
        var n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        if n <= 0 { return nil }
        if Int(n) >= pids.count - 8 {
            pids = [Int32](repeating: 0, count: 16384)
            n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
            if n <= 0 { return nil }
        }
        pids = Array(pids.prefix(Int(n)))
        let me = getuid()

        var procs: [Int32: Proc] = [:]
        procs.reserveCapacity(pids.count)
        for pid in pids where pid > 0 {
            var bi = proc_bsdinfo()
            let r = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, Int32(MemoryLayout<proc_bsdinfo>.size))
            if r == Int32(MemoryLayout<proc_bsdinfo>.size) { procs[pid] = Proc(ppid: Int32(bi.pbi_ppid), uid: bi.pbi_uid) }
        }

        func owner(of pid: Int32) -> Int32? {
            var cur = pid
            var hops = 0
            while hops < 32 {
                if appByPID[cur] != nil { return cur }
                guard let p = procs[cur], p.ppid > 1 else { break }
                cur = p.ppid
                hops += 1
            }
            // Helpers reparented to launchd: match by executable path inside the .app bundle.
            var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
                let path = String(cString: buf)
                for b in bundlePaths where path.hasPrefix(b.prefix) { return b.pid }
            }
            return nil
        }

        let wallNow = nanos(mach_absolute_time())
        var curTimes: [Int32: UInt64] = [:]
        var cpuNs: [Int32: UInt64] = [:]
        var ownNs: [Int32: UInt64] = [:]
        var mem: [Int32: UInt64] = [:]
        var ownMem: [Int32: UInt64] = [:]
        let bundlePrefixByPID = Dictionary(bundlePaths.map { ($0.pid, $0.prefix) }, uniquingKeysWith: { a, _ in a })

        for (pid, p) in procs where p.uid == me {
            guard let appPID = owner(of: pid) else { continue }
            if appPID == ownPID || pid == ownPID { continue }
            var ri = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
            }
            guard ok == 0 else { continue }
            let total = nanos(ri.ri_user_time &+ ri.ri_system_time)
            curTimes[pid] = total
            let prev = prevProcTimes[pid] ?? 0
            let delta = prevProcWall == nil ? 0 : (total >= prev ? total - prev : 0)
            cpuNs[appPID, default: 0] += delta
            // Only count a process as the app's own if it is the app or lives inside its bundle.
            var isOwn = pid == appPID
            if !isOwn, let prefix = bundlePrefixByPID[appPID] {
                var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf).hasPrefix(prefix) { isOwn = true }
            }
            if isOwn {
                if delta > 0 { ownNs[appPID, default: 0] += delta }
                ownMem[appPID, default: 0] += ri.ri_phys_footprint
            }
            mem[appPID, default: 0] += ri.ri_phys_footprint
        }

        let wallDelta = prevProcWall.map { wallNow > $0 ? wallNow - $0 : 0 } ?? 0
        prevProcTimes = curTimes
        prevProcWall = wallNow

        var out: [AppUsage] = []
        for (appPID, app) in appByPID {
            guard let bundleID = app.bundleIdentifier else { continue }
            if let ex = excludedBundleID, bundleID == ex { continue }
            if appPID == ownPID { continue }
            guard let m = mem[appPID] else { continue }
            let cpu = wallDelta > 0 ? Double(cpuNs[appPID] ?? 0) / Double(wallDelta) * 100 : 0
            let own = wallDelta > 0 ? Double(ownNs[appPID] ?? 0) / Double(wallDelta) * 100 : 0
            out.append(AppUsage(name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "App",
                                bundleID: bundleID,
                                cpuPercent: cpu, ownCPUPercent: own, memoryBytes: m, ownMemoryBytes: ownMem[appPID] ?? 0, isFrontmost: appPID == frontPID))
        }
        out.sort { $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.memoryBytes > $1.memoryBytes }
        return out
    }
}
