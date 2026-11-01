import AppKit
import SwiftUI
import PulseCore
import PulseSystem
import PulseActions

/// The one thing every view depends on. In real mode it is fed by the health engine; in demo mode
/// (`--demo` and the design snapshots) it plays made-up scenarios and never touches the Mac.
@MainActor
final class PulseStore: ObservableObject {
    enum Mode { case demo, real }
    let mode: Mode

    @Published var scenario: Scenario = .healthy
    @Published var score = 96
    @Published var fixes: [Fix] = []
    @Published var areas: [Area] = Demo.areas
    @Published var route: Route = .home
    @Published var expanded: String?
    @Published var confirming: String?
    @Published var acknowledged: Set<String> = []
    /// Fixes whose quit request is waiting for the app to close.
    @Published var working: Set<String> = []
    /// The fix whose app would not close; the row is asking about a force quit.
    @Published var forceOffer: String?
    @Published var toast: String?
    @Published var justFixedAll = false
    /// False until the first real report arrives, so nothing wrong is shown in the meantime.
    @Published private(set) var ready: Bool

    @Published var showWelcome = false {
        didSet {
            guard mode == .real, oldValue, !showWelcome else { return }
            defaults.set(true, forKey: Key.welcomeSeen)
            applyLoginItem()
        }
    }
    @Published var startAtLogin = true {
        didSet {
            guard mode == .real, startAtLogin != oldValue, !syncing else { return }
            defaults.set(startAtLogin, forKey: Key.startAtLogin)
            if !showWelcome { applyLoginItem() }
        }
    }
    @Published var notify = true {
        didSet { if mode == .real { defaults.set(notify, forKey: Key.notify) } }
    }
    @Published var isOpen: Bool {
        didSet {
            guard isOpen != oldValue else { return }
            onOpenChange?(isOpen)
            if mode == .real, isOpen { syncLoginItem() }
        }
    }

    /// Set by the app delegate so the scheduler can follow the popover.
    var onOpenChange: ((Bool) -> Void)?

    enum Key {
        static let welcomeSeen = "welcomeSeen"
        static let startAtLogin = "startAtLogin"
        static let notify = "notify"
        static let snoozes = "snoozes"
        static let lastRedNotice = "lastRedNotice"
    }

    private let defaults: UserDefaults
    private let runner = ActionRunner()
    private var syncing = false

    // Real mode plumbing. `core` is only ever touched on `queue`.
    private final class Core: @unchecked Sendable {
        let reader = SystemReader()
        var engine = HealthEngine()
    }
    private struct Apps: @unchecked Sendable { let list: [NSRunningApplication] }
    private let core = Core()
    private let queue = DispatchQueue(label: "com.mokssha.pulse.read", qos: .utility)
    private var reading = false
    private var readAgain = false
    /// After the first quick read, one more that may launch the slower helper commands.
    private var spawnNext = false
    private var lastReadStart = Date.distantPast
    private var lastAreas: [AreaStatus] = []
    private var lastBand: PulseCore.Band?
    private var acted = false
    private var toastToken = 0

    init(mode: Mode, defaults: UserDefaults = .standard) {
        self.mode = mode
        self.defaults = defaults
        ready = mode == .demo
        isOpen = mode == .demo
        guard mode == .real else { return }
        areas = []
        score = 100
        notify = defaults.object(forKey: Key.notify) as? Bool ?? true
        let seen = defaults.bool(forKey: Key.welcomeSeen)
        showWelcome = !seen
        if seen, LoginItem.available { startAtLogin = LoginItem.enabled }
        else { startAtLogin = defaults.object(forKey: Key.startAtLogin) as? Bool ?? true }
        if let data = defaults.data(forKey: Key.snoozes) { try? core.engine.importSnoozes(data) }
    }

    /// True when the menu bar mark should show the sad colour.
    var attention: Bool {
        mode == .demo ? scenario == .attention : (ready && !fixes.isEmpty && score < 65)
    }

    // MARK: Demo

    func load(_ scenario: Scenario) {
        self.scenario = scenario
        route = .home
        expanded = nil
        confirming = nil
        acknowledged = []
        toast = nil
        justFixedAll = false
        switch scenario {
        case .healthy: score = 96; fixes = []
        case .better: score = 76; fixes = [Demo.chrome, Demo.restart]
        case .attention: score = 52; fixes = [Demo.space, Demo.cool, Demo.backups]
        }
    }

    // MARK: Reading (real mode)

    /// Reads the Mac off the main thread and publishes the report. Calls while a read is running are folded into one more.
    func requestRead(minGap: TimeInterval = 0) {
        guard mode == .real else { return }
        if reading { readAgain = true; return }
        guard Date().timeIntervalSince(lastReadStart) >= minGap else { return }
        reading = true
        lastReadStart = Date()
        // NSWorkspace's app list only refreshes with the main run loop, so capture it here.
        let ws = NSWorkspace.shared
        let apps = Apps(list: ws.runningApplications)
        let front = ws.frontmostApplication?.processIdentifier
        // The very first read skips helper commands so the first report appears promptly.
        let spawn = spawnNext || (ready && !isOpen)
        spawnNext = false
        queue.async { [core] in
            let snap = core.reader.read(includeApps: true, allowSpawn: spawn, runningApps: apps.list, frontmostPID: front)
            let report = core.engine.ingest(snap)
            Task { @MainActor [weak self] in self?.finishRead(report) }
        }
    }

    private func finishRead(_ report: Report) {
        reading = false
        let first = !ready
        apply(report)
        if first { spawnNext = true; readAgain = false; requestRead() }
        else if readAgain { readAgain = false; requestRead() }
    }

    private func apply(_ r: Report) {
        let newAreas = r.areas.map(Area.init)
        let previousBand = lastBand
        lastBand = r.band
        if !ready {
            score = r.score; fixes = r.fixes; areas = newAreas; lastAreas = r.areas
            ready = true
        } else {
            if score != r.score { withAnimation(Theme.ringMotion) { score = r.score } }
            if fixes != r.fixes {
                let gone = fixes.contains { f in !r.fixes.contains { $0.id == f.id } }
                withAnimation(Theme.motion) {
                    fixes = r.fixes
                    if r.fixes.isEmpty, gone, acted { justFixedAll = true }
                    if !r.fixes.isEmpty { justFixedAll = false }
                }
            }
            if lastAreas != r.areas { areas = newAreas; lastAreas = r.areas }
        }
        if fixes.isEmpty { acted = false }
        // Forget interface state for fixes that are gone (the condition cleared).
        let live = Set(fixes.map(\.id))
        if let e = expanded, !live.contains(e) { expanded = nil }
        if let c = confirming, !live.contains(c) { confirming = nil }
        if let f = forceOffer, !live.contains(f) { forceOffer = nil }
        if !acknowledged.isSubset(of: live) { acknowledged.formIntersection(live) }
        if !working.isSubset(of: live) { working.formIntersection(live) }
        if r.band == .needsYou, previousBand != .needsYou { notifyIfNeeded(r) }
    }

    // MARK: Actions

    func primary(_ fix: Fix) {
        if mode == .demo { demoPrimary(fix); return }
        if fix.acknowledgeOnly {
            // Nothing to do on the Mac. The row waits and goes away when the Mac recovers.
            withAnimation(Theme.motion) { acknowledged.insert(fix.id); expanded = nil }
        } else if fix.needsConfirm && confirming != fix.id {
            withAnimation(Theme.motion) { confirming = fix.id }
        } else {
            complete(fix)
        }
    }

    /// Runs the fix's action. Only ever reached from a click on its button.
    func complete(_ fix: Fix) {
        if mode == .demo { demoComplete(fix); return }
        withAnimation(Theme.motion) { confirming = nil; expanded = nil }
        guard let action = fix.action else { return }
        switch action {
        case .quitApp(let id, let name):
            withAnimation(Theme.motion) { working.insert(fix.id) }
            Task {
                let result = await runner.quit(bundleID: id, name: name)
                withAnimation(Theme.motion) { working.remove(fix.id) }
                if case .stillRunning = result {
                    withAnimation(Theme.motion) { forceOffer = fix.id }
                } else {
                    finish(result)
                }
            }
        case .restart: Task { finish(await runner.restart()) }
        case .openSettings(let url): finish(runner.openSettings(url))
        case .relaunch(let app): Task { finish(await runner.relaunch(app)) }
        }
    }

    func forceQuit(_ fix: Fix) {
        guard mode == .real, case .quitApp(let id, _)? = fix.action else { return }
        withAnimation(Theme.motion) { forceOffer = nil }
        finish(runner.forceQuit(bundleID: id))
    }

    func cancelForce() { withAnimation(Theme.motion) { forceOffer = nil } }

    /// Reports a failure, and reads again either way. The score only moves when the engine says so.
    private func finish(_ result: ActionResult) {
        switch result {
        case .done: acted = true
        case .refused(let why): showToast(why, seconds: 6)
        case .failed(let why): showToast(why, seconds: 8)
        case .stillRunning: break
        }
        // Give the system a moment to settle (an app closing, a Settings window opening), then look.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.requestRead() }
    }

    func snooze(_ fix: Fix) {
        if mode == .demo {
            withAnimation(Theme.motion) {
                fixes.removeAll { $0.id == fix.id }
                expanded = nil
            }
            showToast("Hidden until tomorrow")
            return
        }
        guard fix.snoozable else { return }
        let id = fix.id
        let defaults = defaults
        queue.async { [core] in
            core.engine.snooze(id, now: Date())
            if let data = try? core.engine.exportSnoozes() { defaults.set(data, forKey: Key.snoozes) }
        }
        withAnimation(Theme.motion) { expanded = nil }
        showToast(SnoozeCopy.toast(for: id))
        requestRead()
    }

    func showToast(_ text: String, seconds: Double = 2.4) {
        toastToken += 1
        let token = toastToken
        withAnimation(Theme.motion) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.toastToken == token else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.toast = nil }
        }
    }

    // MARK: Demo actions (nothing here touches the Mac)

    private func demoPrimary(_ fix: Fix) {
        if fix.acknowledgeOnly {
            withAnimation(Theme.motion) { acknowledged.insert(fix.id); expanded = nil }
            // Pretend the Mac cools off after a while.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.acknowledged.contains(fix.id) else { return }
                self.acknowledged.remove(fix.id)
                self.demoComplete(fix)
            }
        } else if fix.needsConfirm && confirming != fix.id {
            withAnimation(Theme.motion) { confirming = fix.id }
        } else {
            demoComplete(fix)
        }
    }

    private func demoComplete(_ fix: Fix) {
        withAnimation(Theme.motion) {
            fixes.removeAll { $0.id == fix.id }
            confirming = nil
            expanded = nil
            toast = "Demo: nothing on your Mac changed"
        }
        withAnimation(Theme.ringMotion) {
            score = fixes.isEmpty ? max(score + fix.gain, 92) : min(score + fix.gain, 84)
            if fixes.isEmpty { justFixedAll = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
    }

    // MARK: Login item and notices

    private func applyLoginItem() {
        guard LoginItem.available else { return }
        let message = LoginItem.set(startAtLogin)
        syncLoginItem()
        if let message { showToast(message, seconds: 6) }
    }

    private func syncLoginItem() {
        guard LoginItem.available, !showWelcome else { return }
        let actual = LoginItem.enabled
        if actual != startAtLogin {
            syncing = true
            startAtLogin = actual
            syncing = false
            defaults.set(actual, forKey: Key.startAtLogin)
        }
    }

    private func notifyIfNeeded(_ r: Report) {
        guard notify, Notifier.available else { return }
        let last = defaults.double(forKey: Key.lastRedNotice)
        guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
        let first = r.fixes.first
        let body = first.map { "\($0.title.lowercased()): \($0.reason)" } ?? "open pulse to see what to do."
        Task {
            if await Notifier.post(title: "your mac needs you", body: body) {
                defaults.set(Date().timeIntervalSince1970, forKey: Key.lastRedNotice)
            }
        }
    }
}
