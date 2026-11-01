import AppKit
import Combine
import SwiftUI
import PulseCore
import PulseSystem
import ServiceManagement

/// Draws the little character for the menu bar: its mood silhouette with the face cut out.
func buddyMark(size: CGFloat, color: NSColor, band: Band) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        let s = size / 18
        color.setFill()
        let inset = 1.5 * s
        let frame = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        NSBezierPath(cgPath: Silhouette(band: band).path(in: frame).cgPath).fill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.set()
        NSBezierPath(ovalIn: NSRect(x: 5.3 * s, y: 7.5 * s, width: 2 * s, height: 2 * s)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.7 * s, y: 7.5 * s, width: 2 * s, height: 2 * s)).fill()
        // The mouth runs from a smile through flat to a frown.
        let (corner, middle): (CGFloat, CGFloat) = switch band {
        case .good: (11, 12.8)
        case .okay: (12, 12)
        case .poor: (12.8, 11)
        }
        let mouth = NSBezierPath()
        mouth.lineWidth = 1.3 * s
        mouth.lineCapStyle = .round
        mouth.move(to: NSPoint(x: 7 * s, y: corner * s))
        mouth.curve(to: NSPoint(x: 11 * s, y: corner * s),
                    controlPoint1: NSPoint(x: 8 * s, y: middle * s),
                    controlPoint2: NSPoint(x: 10 * s, y: middle * s))
        mouth.stroke()
        return true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let demo = CommandLine.arguments.contains("--demo")
    private var store: PulseStore!
    private var scheduler: Scheduler?
    private var shownBand: Band?
    private var changes: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = PulseStore(mode: demo ? .demo : .real)
        if demo {
            store.load(.healthy)
            store.showWelcome = true
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("Pulse")
        updateIcon()

        let host = NSHostingController(rootView: RootView(store: store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self

        // The menu bar mark follows the store.
        changes = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        store.isOpen = false
        guard !demo else { return }
        let scheduler = Scheduler { [weak self] minGap in self?.store.requestRead(minGap: minGap) }
        self.scheduler = scheduler
        store.onOpenChange = { [weak scheduler] open in scheduler?.setPopoverOpen(open) }
        scheduler.start()
        // Wait a beat so the run loop has refreshed the list of running apps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.store.requestRead() }
    }

    private func updateIcon() {
        let band = store.fixes.isEmpty ? Band.good : Band(score: store.score)
        guard band != shownBand else { return }
        shownBand = band
        // Colour only when the Mac needs the person; otherwise it blends into the menu bar.
        let attention = band == .poor
        let mark = buddyMark(size: 18, color: attention ? NSColor(red: 0.62, green: 0.73, blue: 0.9, alpha: 1) : .black, band: band)
        mark.isTemplate = !attention
        item.button?.image = mark
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            demo ? showDemoMenu() : showQuitMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.isOpen = true
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.isOpen = false
    }

    private func showQuitMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Pulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    // `--demo` only: right-click switcher for trying each state during the design review.
    private func showDemoMenu() {
        let menu = NSMenu()
        for scenario in Scenario.allCases {
            let entry = NSMenuItem(title: scenario.rawValue, action: #selector(pick(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = scenario.rawValue
            entry.state = store.scenario == scenario ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let welcome = NSMenuItem(title: "Show welcome", action: #selector(welcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        menu.addItem(NSMenuItem(title: "Quit Pulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let scenario = Scenario(rawValue: raw) else { return }
        store.showWelcome = false
        store.load(scenario)
        updateIcon()
    }

    @objc private func welcome() {
        store.showWelcome = true
    }
}

Theme.registerFonts()
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--snapshots"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Snapshots.write(to: arguments[i + 1]) }
} else if arguments.contains("--unregister-login") {
    // Used by scripts/uninstall.sh. Harmless when the login item isn't registered.
    try? SMAppService.mainApp.unregister()
} else if arguments.contains("--report") {
    // Headless check of what the real panel would show: two reads, one engine.
    let reader = SystemReader(excludingBundleID: nil)
    var engine = HealthEngine()
    _ = engine.ingest(reader.read())
    Thread.sleep(forTimeInterval: 2)
    let r = engine.ingest(reader.read())
    print("score \(r.score) band \(r.band)")
    for f in r.fixes { print("fix \(f.id): \(f.title) - \(f.reason)") }
    for a in r.areas { print("area \(a.id): \(a.status) \(a.numbers.map { "\($0.label)=\($0.value)" })") }
} else if let i = arguments.firstIndex(of: "--icon"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Snapshots.writeIcon(to: arguments[i + 1]) }
} else {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
