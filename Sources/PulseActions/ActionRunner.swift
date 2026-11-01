import AppKit
import Foundation
import PulseCore

/// What the UI gets back after an attempt.
public enum ActionResult: Sendable, Equatable {
    case done
    case stillRunning(bundleID: String, name: String)
    case refused(reason: String)
    case failed(message: String)
}

/// Pure safety rules, separate from side effects so they can be tested.
public enum ActionPolicy {
    public static let ownBundleID = QuitPolicy.ownBundleID
    public static let neverQuit = QuitPolicy.neverQuit
    public static let relaunchable: Set<String> = ["Finder", "Dock"]

    /// nil means allowed. Delegates to the shared policy the engine also uses.
    public static func quitRefusal(bundleID: String) -> String? { QuitPolicy.refusal(bundleID: bundleID) }

    public static func relaunchRefusal(app: String) -> String? {
        relaunchable.contains(app) ? nil : "Only Finder and Dock can be restarted this way."
    }

    public static func settingsRefusal(url: String) -> String? {
        guard let u = URL(string: url), u.scheme == "x-apple.systempreferences" else {
            return "That isn't a System Settings link."
        }
        return nil
    }
}

/// The only code in Pulse that changes the Mac. Nothing here runs unless the UI calls it
/// in response to a click: no timers, no work on init.
@MainActor
public final class ActionRunner {
    public static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Pulse-actions.log")
    private let waitSeconds: Double

    public init(waitSeconds: Double = 8) { self.waitSeconds = waitSeconds }

    /// Dispatch a FixAction. Quit never force-quits; use `forceQuit` after the person confirms.
    public func run(_ action: FixAction) async -> ActionResult {
        switch action {
        case .quitApp(let id, let name): return await quit(bundleID: id, name: name)
        case .relaunch(let app): return await relaunch(app)
        case .restart: return await restart()
        case .openSettings(let url): return openSettings(url)
        }
    }

    public func quit(bundleID: String, name: String) async -> ActionResult {
        let tag = "quit \(bundleID)"
        if let why = ActionPolicy.quitRefusal(bundleID: bundleID) { return finish(tag, .refused(reason: why)) }
        guard let app = Self.runningApp(bundleID) else { return finish(tag, .done) } // already gone
        guard app.activationPolicy == .regular else {
            return finish(tag, .refused(reason: "This isn't a regular app and can't be quit from here."))
        }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return finish(tag, .refused(reason: "Pulse can't quit itself."))
        }
        guard app.terminate() else { return finish(tag, .failed(message: "\(name) didn't respond to the request.")) }
        let deadline = Date().addingTimeInterval(waitSeconds)
        while !app.isTerminated && Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return finish(tag, app.isTerminated ? .done : .stillRunning(bundleID: bundleID, name: name))
    }

    /// Only call after a click on a dialog that warns about losing unsaved work.
    public func forceQuit(bundleID: String) -> ActionResult {
        let tag = "forceQuit \(bundleID)"
        if let why = ActionPolicy.quitRefusal(bundleID: bundleID) { return finish(tag, .refused(reason: why)) }
        guard let app = Self.runningApp(bundleID) else { return finish(tag, .done) }
        guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return finish(tag, .refused(reason: "This app can't be quit from here."))
        }
        return finish(tag, app.forceTerminate() ? .done : .failed(message: "The app wouldn't close."))
    }

    public func relaunch(_ app: String) async -> ActionResult {
        let tag = "relaunch \(app)"
        if let why = ActionPolicy.relaunchRefusal(app: app) { return finish(tag, .refused(reason: why)) }
        let outcome: ActionResult = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                p.arguments = [app]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                    p.waitUntilExit()
                    cont.resume(returning: p.terminationStatus == 0 ? .done : .failed(message: "\(app) wasn't running."))
                } catch {
                    cont.resume(returning: .failed(message: error.localizedDescription))
                }
            }
        }
        return finish(tag, outcome)
    }

    public func restart() async -> ActionResult {
        let tag = "restart"
        let outcome: ActionResult = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", "tell application \"System Events\" to restart"]
                let errPipe = Pipe()
                p.standardOutput = FileHandle.nullDevice
                p.standardError = errPipe
                do {
                    try p.run()
                } catch {
                    cont.resume(returning: .failed(message: "Couldn't prepare the restart."))
                    return
                }
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 0 { cont.resume(returning: .done); return }
                let text = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.contains("-1743") || text.localizedCaseInsensitiveContains("not authorized") {
                    cont.resume(returning: .failed(message: "Pulse isn't allowed to restart the Mac yet. Allow it in System Settings > Privacy & Security > Automation. (-1743)"))
                } else {
                    let msg = text.isEmpty ? "Restart failed." : text
                    cont.resume(returning: .failed(message: "\(msg) (\(p.terminationStatus))"))
                }
            }
        }
        return finish(tag, outcome)
    }

    public func openSettings(_ urlString: String) -> ActionResult {
        let tag = "open \(urlString)"
        if let why = ActionPolicy.settingsRefusal(url: urlString) {
            return finish(tag, .refused(reason: why))
        }
        guard let url = URL(string: urlString) else { return finish(tag, .refused(reason: "Bad link.")) }
        if NSWorkspace.shared.open(url) { return finish(tag, .done) }
        let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        return finish(tag, NSWorkspace.shared.open(fallback) ? .done : .failed(message: "Couldn't open System Settings."))
    }

    // MARK: helpers

    private static func runningApp(_ id: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first { !$0.isTerminated }
    }

    private func finish(_ what: String, _ r: ActionResult) -> ActionResult {
        let outcome: String
        switch r {
        case .done: outcome = "done"
        case .stillRunning: outcome = "stillRunning"
        case .refused(let s): outcome = "refused: \(s)"
        case .failed(let s): outcome = "failed: \(s)"
        }
        Self.log("\(what) -> \(outcome)")
        return r
    }

    private static func log(_ line: String) {
        let clean = line.replacingOccurrences(of: "\n", with: " ")
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(clean)\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logURL.path) { fm.createFile(atPath: logURL.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(text.utf8))
    }
}
