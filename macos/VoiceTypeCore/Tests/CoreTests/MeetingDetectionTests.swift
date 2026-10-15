import Foundation
import Testing
@testable import Core

@Suite struct MeetingAppsTests {
    @Test func normalizesHelpersToTheirApp() {
        for id in ["com.microsoft.teams2", "com.microsoft.teams2.modulehost", "com.microsoft.teams2.helper"] {
            #expect(MeetingApps.classify(bundleID: id) == MeetingApp(name: "Teams", isBrowser: false))
        }
        #expect(MeetingApps.classify(bundleID: "us.zoom.xos")?.name == "Zoom")
        #expect(MeetingApps.classify(bundleID: "com.tinyspeck.slackmacgap.helper")?.name == "Slack")
    }

    @Test func browsersAreFlagged() {
        #expect(MeetingApps.classify(bundleID: "com.google.Chrome.helper") == MeetingApp(name: "Chrome", isBrowser: true))
        #expect(MeetingApps.classify(bundleID: "com.google.Chrome.canary")?.isBrowser == true)
        #expect(MeetingApps.classify(bundleID: "com.apple.WebKit.GPU") == MeetingApp(name: "Safari", isBrowser: true))
    }

    @Test func platformIsLowercaseAppOrBrowser() {
        #expect(MeetingApps.classify(bundleID: "com.microsoft.teams2.modulehost")?.platform == "teams")
        #expect(MeetingApps.classify(bundleID: "com.apple.FaceTime")?.platform == "facetime")
        #expect(MeetingApps.classify(bundleID: "com.google.Chrome.helper")?.platform == "browser")
        #expect(MeetingApps.classify(bundleID: "com.apple.WebKit.GPU")?.platform == "browser")
    }

    @Test func prefixNeedsADotBoundary() {
        #expect(MeetingApps.classify(bundleID: "com.google.Chromecast") == nil)
        #expect(MeetingApps.classify(bundleID: "com.apple.CoreSpeech") == nil)
        #expect(MeetingApps.classify(bundleID: "") == nil)
    }

    @Test func webRTCSocketRule() {
        #expect(MeetingApps.isWebRTCSocket(localPort: 51019, remotePort: 0))
        #expect(!MeetingApps.isWebRTCSocket(localPort: 5353, remotePort: 0))   // mDNS
        #expect(!MeetingApps.isWebRTCSocket(localPort: 52915, remotePort: 443)) // QUIC
        #expect(!MeetingApps.isWebRTCSocket(localPort: 0, remotePort: 0))
    }
}

@Suite struct MeetingDetectionTests {
    let teams = MeetingApp(name: "Teams", isBrowser: false)
    let chrome = MeetingApp(name: "Chrome", isBrowser: true)
    let t0 = Date(timeIntervalSince1970: 1_000)

    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func startsOnlyAfterStableSignal() {
        var d = MeetingDetection()
        #expect(d.tick(now: at(0), apps: [teams]) == nil)
        #expect(d.tick(now: at(2), apps: [teams]) == nil)
        #expect(d.tick(now: at(4), apps: [teams]) == .started(teams))
        #expect(d.activeApp == teams)
        #expect(d.tick(now: at(6), apps: [teams]) == nil) // once per session
    }

    @Test func flickerDuringPendingResets() {
        var d = MeetingDetection()
        _ = d.tick(now: at(0), apps: [teams])
        _ = d.tick(now: at(2), apps: [])
        #expect(d.tick(now: at(4), apps: [teams]) == nil)
        #expect(d.tick(now: at(6), apps: [teams]) == nil)
        #expect(d.tick(now: at(8), apps: [teams]) == .started(teams))
    }

    @Test func endsAfterGraceNotBefore() {
        var d = MeetingDetection()
        _ = d.tick(now: at(0), apps: [teams])
        _ = d.tick(now: at(4), apps: [teams])
        #expect(d.tick(now: at(10), apps: []) == nil)
        #expect(d.tick(now: at(22), apps: []) == nil) // 18 s since last seen
        #expect(d.tick(now: at(24), apps: []) == .ended(teams))
        #expect(d.activeApp == nil)
    }

    @Test func shortGapKeepsTheSession() {
        var d = MeetingDetection()
        _ = d.tick(now: at(0), apps: [teams])
        _ = d.tick(now: at(4), apps: [teams])
        _ = d.tick(now: at(14), apps: [])
        #expect(d.tick(now: at(20), apps: [teams]) == nil)
        #expect(d.tick(now: at(38), apps: []) == nil) // grace restarts from 20
        #expect(d.tick(now: at(40), apps: []) == .ended(teams))
    }

    @Test func otherAppDoesNotKeepTheMeetingAlive() {
        var d = MeetingDetection()
        _ = d.tick(now: at(0), apps: [teams])
        _ = d.tick(now: at(4), apps: [teams])
        #expect(d.tick(now: at(30), apps: [chrome]) == .ended(teams))
        _ = d.tick(now: at(32), apps: [chrome])
        #expect(d.tick(now: at(36), apps: [chrome]) == .started(chrome))
    }

    @Test func resetForgetsTheSession() {
        var d = MeetingDetection()
        _ = d.tick(now: at(0), apps: [teams])
        _ = d.tick(now: at(4), apps: [teams])
        d.reset()
        #expect(d.activeApp == nil)
        _ = d.tick(now: at(6), apps: [teams])
        #expect(d.tick(now: at(10), apps: [teams]) == .started(teams))
    }
}
