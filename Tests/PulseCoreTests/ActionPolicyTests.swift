import Foundation
import Testing
import PulseCore
@testable import PulseActions

@Suite struct ActionPolicyTests {
    @Test func refusesQuittingPulseItself() {
        #expect(ActionPolicy.quitRefusal(bundleID: ActionPolicy.ownBundleID) != nil)
    }
    @Test func refusesCoreSystemApps() {
        for id in ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow",
                   "com.apple.Terminal", "com.apple.controlcenter"] {
            #expect(ActionPolicy.quitRefusal(bundleID: id) != nil, "\(id)")
        }
    }
    @Test func refusesOtherAppleBundlesThatAreNotUserFacing() {
        #expect(ActionPolicy.quitRefusal(bundleID: "com.apple.WebKit.WebContent") != nil)
        #expect(ActionPolicy.quitRefusal(bundleID: "COM.APPLE.something") != nil)
    }
    @Test func refusesUnidentifiableApps() {
        #expect(ActionPolicy.quitRefusal(bundleID: "") != nil)
        #expect(ActionPolicy.quitRefusal(bundleID: String(repeating: "a", count: 201)) != nil)
    }
    @Test func refusesPidPlaceholderIds() {
        #expect(ActionPolicy.quitRefusal(bundleID: "pid.4242") != nil)
        #expect(!QuitPolicy.isQuittable("pid.1"))
    }
    @Test func actionPolicyAndCorePolicyAgree() {
        for id in ["com.google.Chrome", "com.apple.finder", "com.apple.Safari", "", "pid.9", "com.apple.WebKit.WebContent"] {
            #expect((ActionPolicy.quitRefusal(bundleID: id) == nil) == QuitPolicy.isQuittable(id), "\(id)")
        }
    }
    @Test func allowsOrdinaryApps() {
        for id in ["com.google.Chrome", "com.apple.Safari", "com.apple.mail", "org.mozilla.firefox"] {
            #expect(ActionPolicy.quitRefusal(bundleID: id) == nil, "\(id)")
        }
    }
    @Test func relaunchOnlyFinderAndDock() {
        #expect(ActionPolicy.relaunchRefusal(app: "Finder") == nil)
        #expect(ActionPolicy.relaunchRefusal(app: "Dock") == nil)
        #expect(ActionPolicy.relaunchRefusal(app: "Safari") != nil)
        #expect(ActionPolicy.relaunchRefusal(app: "Finder; rm -rf ~") != nil)
        #expect(ActionPolicy.relaunchRefusal(app: "") != nil)
    }
    @Test func settingsLinksMustBeSystemSettings() {
        #expect(ActionPolicy.settingsRefusal(url: "x-apple.systempreferences:com.apple.settings.Storage") == nil)
        #expect(ActionPolicy.settingsRefusal(url: "https://example.com") != nil)
        #expect(ActionPolicy.settingsRefusal(url: "file:///Applications/Evil.app") != nil)
        #expect(ActionPolicy.settingsRefusal(url: "javascript:alert(1)") != nil)
        #expect(ActionPolicy.settingsRefusal(url: "") != nil)
        #expect(ActionPolicy.settingsRefusal(url: "not a url") != nil)
    }
    @Test func runnerRefusesWithoutTouchingTheMac() async {
        let r = await MainActor.run { ActionRunner(waitSeconds: 0) }
        let quit = await r.quit(bundleID: "com.apple.finder", name: "Finder")
        guard case .refused = quit else { Issue.record("expected refusal, got \(quit)"); return }
        let relaunch = await r.relaunch("Safari")
        guard case .refused = relaunch else { Issue.record("expected refusal, got \(relaunch)"); return }
        let open = await MainActor.run { r.openSettings("https://example.com") }
        guard case .refused = open else { Issue.record("expected refusal, got \(open)"); return }
        let force = await MainActor.run { r.forceQuit(bundleID: "com.apple.dock") }
        guard case .refused = force else { Issue.record("expected refusal, got \(force)"); return }
    }
}
