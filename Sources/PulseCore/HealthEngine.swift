import Foundation

/// Snoozed fixes and when they come back. Codable so the app can keep it across launches.
public struct Snoozes: Codable, Sendable, Equatable {
    public var until: [String: Date] = [:]
    public init(until: [String: Date] = [:]) { self.until = until }
}

/// Turns a stream of snapshots into a calm report. Deterministic: time only comes from the snapshots.
public struct HealthEngine: Sendable {
    // Persistence windows.
    static let memoryWarningWindow: TimeInterval = 5 * 60
    static let memoryCriticalWindow: TimeInterval = 60
    static let runawayWindow: TimeInterval = 5 * 60
    static let thermalSeriousWindow: TimeInterval = 3 * 60
    /// A longer gap between snapshots (sleep) restarts every window. The slowest cadence is 5 minutes
    /// (Low Power Mode), so this must stay above that plus timer tolerance and a slow read.
    static let gapLimit: TimeInterval = 6 * 60
    /// A window also needs this many consecutive readings, so one reading after a pause proves nothing.
    /// Critical memory pressure is exempt: it acts on its short window alone.
    static let minSamples = 3
    static let runawayCPU = 80.0
    static let day: TimeInterval = 86_400
    static let gb = 1_000_000_000.0

    public private(set) var snoozes = Snoozes()
    private var since: [String: Date] = [:]
    private var samples: [String: Int] = [:]
    private var lastDate: Date?

    public init() {}

    // MARK: Snooze

    public mutating func snooze(_ fixID: String, now: Date) {
        snoozes.until[fixID] = now.addingTimeInterval(SnoozeCopy.length(for: fixID))
    }

    public mutating func restoreSnoozes(_ saved: Snoozes) { snoozes = saved }

    public func exportSnoozes() throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return try enc.encode(snoozes)
    }

    public mutating func importSnoozes(_ data: Data) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        snoozes = try dec.decode(Snoozes.self, from: data)
    }

    // MARK: Ingest

    private struct Candidate { var fix: Fix; var area: String }

    public mutating func ingest(_ s: Snapshot) -> Report {
        let now = s.date
        if let last = lastDate, now.timeIntervalSince(last) > Self.gapLimit { since.removeAll(); samples.removeAll() }
        lastDate = now
        snoozes.until = snoozes.until.filter { $0.value > now }

        var found: [Candidate] = []
        func add(_ f: Fix, _ area: String) { found.append(Candidate(fix: f, area: area)) }

        // Memory pressure: pick one app to quit.
        let warn = held("mem.warn", s.memoryPressure.map { $0 >= .warning }, now)
        let crit = held("mem.crit", s.memoryPressure.map { $0 == .critical }, now, minSamples: 1)
        let memCritical = (crit ?? 0) >= Self.memoryCriticalWindow
        let memWarn = (warn ?? 0) >= Self.memoryWarningWindow
        if memCritical || memWarn, let target = Self.heaviest(s.apps) {
            add(Copy.quitHeavy(target, critical: memCritical), "Speed")
        }

        // Runaway apps, never the one in front.
        if let apps = s.apps {
            var live = Set<String>()
            for a in apps where Self.isRunaway(a) { live.insert("run.\(a.bundleID)") }
            for key in since.keys where key.hasPrefix("run.") && !live.contains(key) { since[key] = nil; samples[key] = nil }
            for a in apps where live.contains("run.\(a.bundleID)") {
                if (held("run.\(a.bundleID)", true, now) ?? 0) >= Self.runawayWindow {
                    add(Copy.quitBusy(a), "Speed")
                }
            }
        }

        // Heat.
        let hot = held("therm.serious", s.thermal.map { $0 >= .serious }, now)
        if s.thermal == .critical || (hot ?? 0) >= Self.thermalSeriousWindow, s.thermal != nil {
            add(Copy.cool(critical: s.thermal == .critical), "Heat")
        }

        // Hardware only: how full the disk is stays in Details, a failing disk counts.
        var freePct: Double?
        if let f = s.freeBytes, let t = s.totalBytes, t > 0 { freePct = Double(f) / Double(t) }
        if s.diskHealthy == false { add(Copy.diskFailing(), "Storage") }

        // Battery.
        if let b = s.battery, b.present {
            let low = b.maxCapacityPercent.map { $0 < 80 } ?? false
            if b.serviceRecommended == true || low {
                add(Copy.battery(service: b.serviceRecommended == true), "Battery")
            }
        }

        // Restart.
        if let up = s.uptime, up >= 14 * Self.day {
            add(Copy.restart(days: Int(up / Self.day), serious: up >= 45 * Self.day), "Speed")
        }

        let active = Self.merge(found)
        let visible = active.filter { !$0.fix.snoozable || snoozes.until[$0.fix.id] == nil }
        var score = 100 - visible.reduce(0) { $0 + Self.deduction($1.fix.priority) } - Self.softDeduction(s, freePct: freePct)
        score = max(0, min(100, score))
        if !visible.isEmpty { score = min(score, 84) }
        let top = Array(visible.prefix(3).map(\.fix))
        return Report(score: score, band: .forScore(score), fixes: top,
                      areas: Areas.build(s, active: active.map { ($0.fix, $0.area) }, freePct: freePct))
    }

    // MARK: Helpers

    /// How long a condition has held, nil when the reading is unavailable (state is left alone).
    /// Reports 0 until `minSamples` consecutive readings have seen it.
    private mutating func held(_ key: String, _ condition: Bool?, _ now: Date, minSamples: Int = HealthEngine.minSamples) -> TimeInterval? {
        guard let condition else { return nil }
        if !condition { since[key] = nil; samples[key] = nil; return 0 }
        let start = since[key] ?? now
        since[key] = start
        let n = (samples[key] ?? 0) + 1
        samples[key] = n
        return n >= minSamples ? now.timeIntervalSince(start) : 0
    }

    /// Busy by its own processes, and not the app in front. Terminal or editor jobs don't count.
    static func isRunaway(_ a: AppUsage) -> Bool {
        (a.ownCPUPercent ?? a.cpuPercent) > runawayCPU && !a.isFrontmost && QuitPolicy.isQuittable(a.bundleID)
    }

    /// The biggest app that may actually be quit, preferring one that isn't in front.
    static func heaviest(_ apps: [AppUsage]?) -> AppUsage? {
        guard let apps else { return nil }
        let ok = apps.filter { QuitPolicy.isQuittable($0.bundleID) }
        guard !ok.isEmpty else { return nil }
        let pool = ok.contains { !$0.isFrontmost } ? ok.filter { !$0.isFrontmost } : ok
        return pool.max { ($0.ownMemoryBytes ?? $0.memoryBytes) < ($1.ownMemoryBytes ?? $1.memoryBytes) }
    }

    /// Merge fixes with the same action (keep the worst), then order by priority.
    private static func merge(_ all: [Candidate]) -> [Candidate] {
        func worse(_ a: Candidate, _ b: Candidate) -> Bool {
            if a.fix.priority != b.fix.priority { return a.fix.priority > b.fix.priority }
            if a.fix.gain != b.fix.gain { return a.fix.gain > b.fix.gain }
            return a.fix.id < b.fix.id
        }
        var kept: [Candidate] = []
        for c in all {
            guard let key = c.fix.action?.key else { kept.append(c); continue }
            if let i = kept.firstIndex(where: { $0.fix.action?.key == key }) {
                if worse(c, kept[i]) { kept[i] = c }
            } else { kept.append(c) }
        }
        return kept.sorted(by: worse)
    }

    static func deduction(_ p: FixPriority) -> Int { p == .warn ? 16 : 36 }

    /// A few points at most, for things that are close to a problem. Never creates a fix.
    private static func softDeduction(_ s: Snapshot, freePct: Double?) -> Int {
        var d = 0
        if let u = s.uptime, u >= 7 * day { d += 1 }
        if s.thermal == .fair { d += 1 }
        return min(d, 4)
    }
}
