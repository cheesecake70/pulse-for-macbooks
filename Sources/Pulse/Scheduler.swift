import AppKit
import IOKit.ps

/// Decides when to read the Mac. Quiet by default: once a minute, slower on battery and in Low Power
/// Mode, quicker while the popover is open, stopped while the Mac sleeps. Heat and memory pressure
/// trigger an immediate read.
@MainActor
final class Scheduler {
    private let fire: (_ minGap: TimeInterval) -> Void
    private var timer: DispatchSourceTimer?
    private var memorySource: DispatchSourceMemoryPressure?
    private var powerSource: CFRunLoopSource?
    private var asleep = false
    private var popoverOpen = false
    private var onBattery = false
    private var lowPower = false
    private var observers: [NSObjectProtocol] = []

    init(fire: @escaping (_ minGap: TimeInterval) -> Void) { self.fire = fire }

    /// Seconds between reads in the current situation.
    var interval: TimeInterval {
        if popoverOpen { return 3 }
        if lowPower { return 300 }
        if onBattery { return 120 }
        return 60
    }

    func start() {
        onBattery = Self.runningOnBattery()
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true; self?.reschedule() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.asleep = false
                self.onBattery = Self.runningOnBattery()
                self.reschedule()
                // Let the network and disks settle, then look once.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.fire(0) }
            }
        })
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(5) }
        })
        observers.append(nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.isLowPowerModeEnabled
                if now != self.lowPower { self.lowPower = now; self.reschedule() }
            }
        })

        let mem = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        mem.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.fire(5) } }
        mem.resume()
        memorySource = mem

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<Scheduler>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                let now = Scheduler.runningOnBattery()
                if now != me.onBattery { me.onBattery = now; me.reschedule() }
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }
        reschedule()
    }

    func setPopoverOpen(_ open: Bool) {
        guard open != popoverOpen else { return }
        popoverOpen = open
        reschedule()
        if open { fire(0) }
    }

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard !asleep else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        let every = interval
        // Generous tolerance when idle lets the system coalesce wakeups with other work.
        t.schedule(deadline: .now() + every, repeating: every, leeway: popoverOpen ? .milliseconds(500) : .seconds(15))
        t.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.fire(0) } }
        t.resume()
        timer = t
    }

    nonisolated static func runningOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }
}
