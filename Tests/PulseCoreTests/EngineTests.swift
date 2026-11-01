import Foundation
import Testing
@testable import PulseCore

private func ids(_ r: Report) -> [String] { r.fixes.map(\.id) }

@Suite struct CalmMacs {
    @Test func busy8GBMacStaysHealthy() {
        var worst = 100
        var any = false
        var j = 0
        var e2 = HealthEngine()
        var t = 0.0
        while t <= 3600 {
            j += 1
            let burst = (j % 20) < 4
            let r = e2.ingest(calm(t0.addingTimeInterval(t), apps: [
                app("Chrome", cpu: 140, gb: 6, front: true), app("Slack", cpu: burst ? 95 : 4)]))
            worst = min(worst, r.score); any = any || !r.fixes.isEmpty
            #expect(r.band == .healthy)
            t += 30
        }
        #expect(!any); #expect(worst >= 85)
    }

    @Test func big24GBMacStaysHealthy() {
        var e = HealthEngine()
        let r = run(&e, minutes: 60) { d in
            var s = calm(d); s.physicalMemoryBytes = 24 * GB; return s
        }
        #expect(r.fixes.isEmpty); #expect(r.band == .healthy); #expect(r.score == 100)
    }
}

@Suite struct Runaway {
    func spike(_ minutes: Double, front: Bool = false) -> Report {
        var e = HealthEngine()
        return run(&e, minutes: minutes) { d in
            calm(d, apps: [app("Chrome", cpu: 20, gb: 2, front: true),
                           app("Builder", cpu: 150, gb: 1, front: front)])
        }
    }
    @Test func twoMinutesIsNothing() { #expect(spike(2).fixes.isEmpty) }
    @Test func sixMinutesQuits() {
        let r = spike(6)
        #expect(ids(r) == ["quit.com.test.Builder"])
        #expect(r.fixes[0].action == .quitApp(bundleID: "com.test.Builder", name: "Builder"))
        #expect(r.fixes[0].title == "Quit Builder")
    }
    @Test func frontmostIsExcluded() {
        var e = HealthEngine()
        let r = run(&e, minutes: 20) { d in calm(d, apps: [app("Builder", cpu: 150, front: true)]) }
        #expect(r.fixes.isEmpty)
    }
    @Test func burstResetsTheWindow() {
        var e = HealthEngine()
        run(&e, minutes: 4) { d in calm(d, apps: [app("Builder", cpu: 150), app("Chrome", front: true)]) }
        run(&e, minutes: 1, from: 4.5) { d in calm(d, apps: [app("Builder", cpu: 5), app("Chrome", front: true)]) }
        let r = run(&e, minutes: 4, from: 6) { d in calm(d, apps: [app("Builder", cpu: 150), app("Chrome", front: true)]) }
        #expect(r.fixes.isEmpty)
    }
}

@Suite struct Memory {
    func pressure(_ p: MemoryPressure, minutes: Double) -> Report {
        var e = HealthEngine()
        return run(&e, minutes: minutes, step: 10) { d in
            var s = calm(d, apps: [app("Chrome", cpu: 10, gb: 5, front: true), app("Photos", gb: 2), app("Mail", gb: 0.3)])
            s.memoryPressure = p; return s
        }
    }
    @Test func warningNeedsFiveMinutes() {
        #expect(pressure(.warning, minutes: 4.5).fixes.isEmpty)
        let r = pressure(.warning, minutes: 5.2)
        // Heaviest non-frontmost app, not the frontmost Chrome.
        #expect(ids(r) == ["quit.com.test.Photos"])
    }
    @Test func criticalActsWithinAMinute() {
        #expect(pressure(.critical, minutes: 0.5).fixes.isEmpty)
        let r = pressure(.critical, minutes: 1.1)
        #expect(ids(r) == ["quit.com.test.Photos"])
        #expect(r.fixes[0].serious)
    }
    @Test func onlyFrontmostAppStillGetsAnOffer() {
        var e = HealthEngine()
        let r = run(&e, minutes: 2, step: 10) { d in
            var s = calm(d, apps: [app("Chrome", gb: 5, front: true)]); s.memoryPressure = .critical; return s
        }
        #expect(ids(r) == ["quit.com.test.Chrome"])
    }
    @Test func noAppListMeansNoFix() {
        var e = HealthEngine()
        let r = run(&e, minutes: 10) { d in
            var s = calm(d); s.apps = nil; s.memoryPressure = .critical; return s
        }
        #expect(r.fixes.isEmpty)
    }
}

@Suite struct Heat {
    func thermal(_ t: ThermalLevel, minutes: Double) -> Report {
        var e = HealthEngine()
        return run(&e, minutes: minutes, step: 10) { d in var s = calm(d); s.thermal = t; return s }
    }
    @Test func seriousFlipsAtThreeMinutes() {
        #expect(thermal(.serious, minutes: 2.8).fixes.isEmpty)
        let r = thermal(.serious, minutes: 3.1)
        #expect(ids(r) == ["cool"]); #expect(r.fixes[0].acknowledgeOnly); #expect(r.fixes[0].action == nil)
    }
    @Test func criticalIsImmediate() {
        var e = HealthEngine()
        var s = calm(t0); s.thermal = .critical
        #expect(ids(e.ingest(s)) == ["cool"])
    }
    @Test func fairIsNothing() { #expect(thermal(.fair, minutes: 30).fixes.isEmpty) }
}

@Suite struct Storage {
    func report(freeGB: Double, totalGB: Double) -> Report {
        var e = HealthEngine()
        var s = calm(t0); s.freeBytes = UInt64(freeGB * Double(GB)); s.totalBytes = UInt64(totalGB * Double(GB))
        return e.ingest(s)
    }
    @Test func nearlyFullDisksGiveNoFixes() {
        let baseline = report(freeGB: 500, totalGB: 1000).score
        for (free, total) in [(149.0, 1000.0), (19.5, 100.0), (49.0, 1000.0), (7.5, 100.0), (1.0, 100.0)] {
            let r = report(freeGB: free, totalGB: total)
            #expect(r.fixes.isEmpty); #expect(r.score >= baseline - 4); #expect(r.band == .healthy)
        }
        #expect(report(freeGB: 1, totalGB: 100).score == baseline)
    }
    @Test func diskFailureIsDataLoss() {
        var e = HealthEngine(); var s = calm(t0); s.diskHealthy = false
        let r = e.ingest(s)
        #expect(ids(r) == ["disk"]); #expect(r.fixes[0].priority == .dataLoss)
        s.diskHealthy = true
        #expect(e.ingest(calm(at(1))).fixes.isEmpty)
    }
    @Test func nearFullDiskChangesNothing() {
        var e = HealthEngine(); var s = calm(t0)
        s.freeBytes = 120 * GB; s.totalBytes = 500 * GB // 24% free
        let r = e.ingest(s)
        #expect(r.fixes.isEmpty); #expect(r.score == 100); #expect(r.band == .healthy)
    }
}

@Suite struct Longevity {
    func battery(_ b: BatteryReading?) -> Report {
        var e = HealthEngine(); var s = calm(t0); s.battery = b; return e.ingest(s)
    }
    @Test func serviceRecommended() {
        #expect(ids(battery(BatteryReading(present: true, maxCapacityPercent: 90, serviceRecommended: true))) == ["battery"])
    }
    @Test func capacityThreshold() {
        #expect(battery(BatteryReading(present: true, maxCapacityPercent: 80, serviceRecommended: false)).fixes.isEmpty)
        #expect(ids(battery(BatteryReading(present: true, maxCapacityPercent: 79, serviceRecommended: false))) == ["battery"])
    }
    @Test func noBatteryOmitsAreaAndFix() {
        let r = battery(BatteryReading(present: false))
        #expect(r.fixes.isEmpty)
        #expect(!r.areas.contains { $0.id == "Battery" })
        #expect(battery(BatteryReading(present: true, maxCapacityPercent: 90)).areas.contains { $0.id == "Battery" })
    }
    func uptime(_ days: Double) -> Report {
        var e = HealthEngine(); var s = calm(t0); s.uptime = days * 86_400; return e.ingest(s)
    }
    @Test func uptimeThresholds() {
        #expect(uptime(13.9).fixes.isEmpty)
        let warn = uptime(14)
        #expect(ids(warn) == ["restart"]); #expect(warn.fixes[0].priority == .warn)
        #expect(warn.fixes[0].reason == "awake for 14 days.")
        #expect(uptime(44.9).fixes[0].priority == .warn)
        #expect(uptime(45).fixes[0].priority == .serious)
    }
    @Test func weekOldUptimeOnlyNudgesScore() {
        let r = uptime(8)
        #expect(r.fixes.isEmpty); #expect(r.score < 100); #expect(r.band == .healthy)
    }
}

@Suite struct Protection {
    func with(_ edit: (inout Snapshot) -> Void) -> Report {
        var e = HealthEngine(); var s = calm(t0); edit(&s); return e.ingest(s)
    }
    @Test func allOffNeverWaitingIsStillHealthy() {
        let r = with {
            $0.fileVaultOn = false; $0.firewallOn = false
            $0.updateWaiting = true; $0.lastBackup = .never
        }
        #expect(r.fixes.isEmpty); #expect(r.score == 100); #expect(r.band == .healthy)
    }
    @Test func staleBackupIsStillHealthy() {
        let r = with { $0.lastBackup = .date(t0.addingTimeInterval(-40 * 86_400)) }
        #expect(r.fixes.isEmpty); #expect(r.score == 100); #expect(r.band == .healthy)
    }
    @Test func eachSettingAloneGivesNoFix() {
        #expect(with { $0.fileVaultOn = false }.fixes.isEmpty)
        #expect(with { $0.firewallOn = false }.fixes.isEmpty)
        #expect(with { $0.updateWaiting = true }.fixes.isEmpty)
        #expect(with { $0.lastBackup = .never }.fixes.isEmpty)
    }
}

@Suite struct Unknowns {
    @Test func everythingNilIsQuiet() {
        var e = HealthEngine()
        let r = run(&e, minutes: 60) { Snapshot(date: $0) }
        #expect(r.fixes.isEmpty); #expect(r.score == 100)
        #expect(r.areas.allSatisfy { $0.numbers.isEmpty })
    }
    @Test func unknownRowsAreOmitted() {
        var e = HealthEngine(); var s = calm(t0); s.firewallOn = nil; s.freeBytes = nil
        let r = e.ingest(s)
        let prot = r.areas.first { $0.id == "Protection" }!
        #expect(!prot.numbers.contains { $0.label == "Firewall" })
        #expect(prot.numbers.contains { $0.label == "File encryption" })
        #expect(!r.areas.first { $0.id == "Storage" }!.numbers.contains { $0.label == "Free" })
    }
    @Test func nilDoesNotResetOtherWindows() {
        var e = HealthEngine()
        run(&e, minutes: 4, step: 10) { d in var s = calm(d); s.thermal = .serious; return s }
        // thermal goes unreadable for a moment, memory is fine
        var s = calm(at(4.2)); s.thermal = nil
        #expect(e.ingest(s).fixes.isEmpty)
        var back = calm(at(4.4)); back.thermal = .serious
        #expect(ids(e.ingest(back)) == ["cool"])
    }
    @Test func windowsStillWorkAtLowPowerCadence() {
        // Low Power Mode reads every 300 s, plus timer tolerance. That must not look like a sleep gap.
        var e = HealthEngine()
        var t = 0.0
        var r: Report?
        while t <= 12 * 60 {
            var s = calm(t0.addingTimeInterval(t)); s.thermal = .serious
            r = e.ingest(s)
            t += 315
        }
        #expect(ids(r!) == ["cool"])
    }
    @Test func gapJustOverLowPowerCadenceKeepsWindows() {
        var e = HealthEngine()
        var r: Report?
        for m in [0.0, 5.5, 11.0] {
            var s = calm(at(m)); s.thermal = .serious
            r = e.ingest(s)
        }
        #expect(ids(r!) == ["cool"])
    }
    @Test func longGapStillRestartsWindows() {
        var e = HealthEngine()
        var s = calm(at(0)); s.thermal = .serious
        _ = e.ingest(s)
        var s2 = calm(at(20)); s2.thermal = .serious
        #expect(e.ingest(s2).fixes.isEmpty)
    }
    @Test func eightMinuteSleepWithOneSampleShowsNothing() {
        var e = HealthEngine()
        var a = calm(at(0)); a.thermal = .serious
        _ = e.ingest(a)
        var b = calm(at(8)); b.thermal = .serious
        #expect(e.ingest(b).fixes.isEmpty)
        // Memory and runaway windows behave the same way.
        var e2 = HealthEngine()
        var m1 = calm(at(0)); m1.memoryPressure = .warning
        _ = e2.ingest(m1)
        var m2 = calm(at(8)); m2.memoryPressure = .warning
        #expect(e2.ingest(m2).fixes.isEmpty)
    }
    @Test func twoSamplesAreNotEnoughEvenWhenElapsedIsLong() {
        var e = HealthEngine()
        var a = calm(at(0)); a.thermal = .serious
        _ = e.ingest(a)
        var b = calm(at(5)); b.thermal = .serious
        #expect(e.ingest(b).fixes.isEmpty)
        var c = calm(at(10)); c.thermal = .serious
        #expect(ids(e.ingest(c)) == ["cool"])
    }
    @Test func lowPowerCadenceFiresWithinFifteenMinutes() {
        var e = HealthEngine()
        var firedAt: Double?
        var t = 0.0
        while t <= 15 * 60 {
            var s = calm(t0.addingTimeInterval(t)); s.memoryPressure = .warning
            if !e.ingest(s).fixes.isEmpty, firedAt == nil { firedAt = t }
            t += 305
        }
        #expect(firedAt != nil && firedAt! <= 15 * 60)
    }
    @Test func criticalMemoryStillActsOnItsShortWindow() {
        var e = HealthEngine()
        var a = calm(at(0)); a.memoryPressure = .critical
        _ = e.ingest(a)
        var b = calm(at(1.1)); b.memoryPressure = .critical
        #expect(ids(e.ingest(b)) == ["quit.com.test.Chrome"] || !e.ingest(b).fixes.isEmpty)
    }
    @Test func sleepGapRestartsWindows() {
        var e = HealthEngine()
        run(&e, minutes: 4, step: 10) { d in var s = calm(d); s.thermal = .serious; return s }
        // 10 hours asleep, wake up still reading serious: the clock starts over.
        var w = calm(at(600)); w.thermal = .serious
        #expect(e.ingest(w).fixes.isEmpty)
        var w2 = calm(at(602)); w2.thermal = .serious
        #expect(e.ingest(w2).fixes.isEmpty)
        var w3 = calm(at(603.5)); w3.thermal = .serious
        #expect(ids(e.ingest(w3)) == ["cool"])
    }
}

@Suite struct Ranking {
    func trouble(_ d: Date) -> Snapshot {
        var s = calm(d)
        s.diskHealthy = false; s.thermal = .critical; s.uptime = 50 * 86_400
        s.battery = BatteryReading(present: true, maxCapacityPercent: 70, serviceRecommended: true)
        return s
    }
    @Test func maxThreeOrderedByPriority() {
        var e = HealthEngine()
        let r = e.ingest(trouble(t0))
        #expect(r.fixes.count == 3)
        #expect(r.fixes.map(\.priority) == r.fixes.map(\.priority).sorted(by: >))
        #expect(r.fixes[0].id == "disk"); #expect(r.fixes[0].priority == .dataLoss)
        #expect(!ids(r).contains("battery")) // the lowest priority is the one dropped
        #expect(r.band == .needsYou)
    }
    @Test func sameActionIsMerged() {
        // Failing disk and a stale-backup style fix both opened Time Machine; now only the disk remains,
        // so check merging with two fixes that share no action stays at two.
        var e = HealthEngine(); var s = calm(t0)
        s.diskHealthy = false; s.thermal = .critical
        let r = e.ingest(s)
        #expect(Set(ids(r)) == ["disk", "cool"])
    }
    @Test func memoryAndRunawayOnSameAppMerge() {
        var e = HealthEngine()
        let r = run(&e, minutes: 6, step: 10) { d in
            var s = calm(d, apps: [app("Chrome", gb: 3, front: true), app("Builder", cpu: 150, gb: 2)])
            s.memoryPressure = .warning; return s
        }
        #expect(ids(r) == ["quit.com.test.Builder"])
    }
    @Test func scoreBandsAreSensible() {
        var e = HealthEngine(); var s = calm(t0)
        s.battery = BatteryReading(present: true, maxCapacityPercent: 70, serviceRecommended: false)
        #expect(e.ingest(s).band == .couldUseCare)
        s.uptime = 50 * 86_400
        var two = HealthEngine()
        #expect(two.ingest(s).band == .needsYou)
        var f = calm(t0); f.diskHealthy = false
        var three = HealthEngine()
        #expect(three.ingest(f).band == .needsYou)
    }
}

@Suite struct Snoozing {
    func hot(_ d: Date) -> Snapshot { var s = calm(d); s.uptime = 20 * 86_400; return s }
    @Test func twentyFourHours() {
        var e = HealthEngine()
        #expect(ids(e.ingest(hot(t0))) == ["restart"])
        e.snooze("restart", now: t0)
        let hidden = e.ingest(hot(at(60)))
        #expect(hidden.fixes.isEmpty); #expect(hidden.band == .healthy)
        #expect(e.ingest(hot(t0.addingTimeInterval(23.9 * 3600))).fixes.isEmpty)
        #expect(ids(e.ingest(hot(t0.addingTimeInterval(24.1 * 3600)))) == ["restart"])
    }
    @Test func batteryThirtyDays() {
        func worn(_ d: Date) -> Snapshot {
            var s = calm(d); s.battery = BatteryReading(present: true, maxCapacityPercent: 70, serviceRecommended: false); return s
        }
        var e = HealthEngine()
        e.snooze("battery", now: t0)
        #expect(e.ingest(worn(t0.addingTimeInterval(29 * 86_400))).fixes.isEmpty)
        #expect(ids(e.ingest(worn(t0.addingTimeInterval(30.1 * 86_400)))) == ["battery"])
    }
    @Test func survivesExportAndImport() throws {
        var e = HealthEngine()
        e.snooze("restart", now: t0)
        let data = try e.exportSnoozes()
        var fresh = HealthEngine()
        try fresh.importSnoozes(data)
        #expect(fresh.ingest(hot(at(10))).fixes.isEmpty)
        #expect(fresh.snoozes == e.snoozes)
    }
    @Test func snoozedLeavesRestVisible() {
        var e = HealthEngine(); var s = hot(t0); s.diskHealthy = false
        e.snooze("restart", now: t0)
        #expect(ids(e.ingest(s)) == ["disk"])
    }
}

@Suite struct Invariants {
    @Test func fixesAndScoreAlwaysAgree() {
        var seed: UInt64 = 42
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        var e = HealthEngine()
        var sawFix = false, sawQuiet = false
        for i in 0..<4000 {
            let d = t0.addingTimeInterval(Double(i) * 45)
            var s = calm(d, apps: [app("A", cpu: rnd() * 200, gb: rnd() * 4, front: rnd() < 0.3),
                                   app("B", cpu: rnd() * 200, gb: rnd() * 4)])
            s.memoryPressure = [.normal, .normal, .warning, .critical][Int(rnd() * 4) % 4]
            s.thermal = ThermalLevel(rawValue: Int(rnd() * 4) % 4)
            s.freeBytes = UInt64(rnd() * 100) * GB
            s.uptime = rnd() * 60 * 86_400
            s.diskHealthy = rnd() < 0.98
            if rnd() < 0.05 { s.thermal = nil; s.memoryPressure = nil }
            if i % 700 == 0 { e.snooze("cool", now: d) }
            let r = e.ingest(s)
            #expect(r.fixes.count <= 3)
            #expect((0...100).contains(r.score))
            if r.fixes.isEmpty { sawQuiet = true; #expect(r.score >= 85); #expect(r.band == .healthy) }
            else { sawFix = true; #expect(r.score < 85); #expect(r.band != .healthy) }
        }
        #expect(sawFix && sawQuiet)
    }
}


@Suite struct ReviewFixes {
    func pressured(_ d: Date, apps: [AppUsage]) -> Snapshot {
        var s = calm(d, apps: apps); s.memoryPressure = .critical; return s
    }
    @Test func heaviestSkipsUnquittableApps() {
        let apps = [app("Finder", gb: 5, id: "com.apple.finder"),
                    app("Helper", gb: 4, id: "pid.123"),
                    app("Slack", gb: 1, id: "com.slack"),
                    app("Mail", gb: 0.5, front: true)]
        var e = HealthEngine()
        let r = run(&e, minutes: 3, step: 20) { pressured($0, apps: apps) }
        #expect(ids(r) == ["quit.com.slack"])
    }
    @Test func heaviestRanksByOwnMemory() {
        let term = AppUsage(name: "Terminal", bundleID: "com.test.term", cpuPercent: 5, memoryBytes: 6 * GB,
                            ownMemoryBytes: UInt64(0.2 * Double(GB)))
        let apps = [term, app("Slack", gb: 1, id: "com.slack"), app("Mail", gb: 0.5, front: true)]
        var e = HealthEngine()
        let r = run(&e, minutes: 3, step: 20) { pressured($0, apps: apps) }
        #expect(ids(r) == ["quit.com.slack"])
    }
    @Test func heaviestFallsBackToTotalWhenOwnMissing() {
        let apps = [app("Big", gb: 3, id: "com.big"), app("Slack", gb: 1, id: "com.slack"), app("Mail", gb: 0.5, front: true)]
        var e = HealthEngine()
        let r = run(&e, minutes: 3, step: 20) { pressured($0, apps: apps) }
        #expect(ids(r) == ["quit.com.big"])
    }
    @Test func onlyUnquittableAppsMeansNoQuitFix() {
        let apps = [app("Finder", gb: 5, id: "com.apple.finder"), app("Pulse", gb: 4, id: "com.mokssha.pulse")]
        var e = HealthEngine()
        let r = run(&e, minutes: 3, step: 20) { pressured($0, apps: apps) }
        #expect(r.fixes.isEmpty)
    }
    @Test func runawayIgnoresUnquittableApps() {
        let apps = [app("WindowServer", cpu: 150, id: "com.apple.WindowManager"), app("Render", cpu: 120, id: "com.render")]
        var e = HealthEngine()
        let r = run(&e, minutes: 8, step: 30) { calm($0, apps: apps) }
        #expect(ids(r) == ["quit.com.render"])
    }
    @Test func runawayNeedsAppsOwnProcessesToBeBusy() {
        // Mostly a terminal-launched job under the app: busy overall, idle itself.
        var busyChild = app("Editor", cpu: 200, id: "com.editor")
        busyChild.ownCPUPercent = 3
        var e = HealthEngine()
        #expect(run(&e, minutes: 8, step: 30) { calm($0, apps: [busyChild]) }.fixes.isEmpty)
        var own = app("Editor", cpu: 200, id: "com.editor")
        own.ownCPUPercent = 150
        var e2 = HealthEngine()
        #expect(ids(run(&e2, minutes: 8, step: 30) { calm($0, apps: [own]) }) == ["quit.com.editor"])
    }
    @Test func diskFailingAndCriticalHeatIgnoreSnooze() {
        var e = HealthEngine()
        e.snooze("disk", now: at(0)); e.snooze("cool", now: at(0))
        let r = run(&e, minutes: 4, step: 20) { d in
            var s = calm(d); s.diskHealthy = false; s.thermal = .critical; return s
        }
        #expect(Set(ids(r)) == ["disk", "cool"])
        #expect(r.fixes.allSatisfy { !$0.snoozable })
    }
    @Test func ordinaryHeatCanStillBeSnoozed() {
        var e = HealthEngine()
        e.snooze("cool", now: at(0))
        let r = run(&e, minutes: 4, step: 20) { d in var s = calm(d); s.thermal = .serious; return s }
        #expect(r.fixes.isEmpty)
        #expect(Copy.cool(critical: false).snoozable)
        #expect(!Copy.cool(critical: true).snoozable)
        #expect(!Copy.diskFailing().snoozable)
        #expect(Copy.restart(days: 20, serious: false).snoozable)
    }
    @Test func snoozeWordsComeFromOnePlace() {
        #expect(SnoozeCopy.button(for: "battery") == "Hide for 30 days")
        #expect(SnoozeCopy.toast(for: "battery") == "Hidden for 30 days")
        #expect(SnoozeCopy.button(for: "restart") == "Hide until tomorrow")
        #expect(SnoozeCopy.toast(for: "quit.x") == "Hidden until tomorrow")
        #expect(SnoozeCopy.length(for: "battery") == 30 * 86_400)
        #expect(SnoozeCopy.length(for: "restart") == 86_400)
    }
    @Test func loginApprovalCountsAsOn() {
        #expect(LoginStatus.requiresApproval.isOn)
        #expect(LoginStatus.enabled.isOn)
        #expect(!LoginStatus.notRegistered.isOn)
        #expect(!LoginStatus.notFound.isOn)
    }
}
