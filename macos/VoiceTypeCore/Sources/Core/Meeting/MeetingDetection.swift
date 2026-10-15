import Foundation

/// A meeting-capable app, normalized from any of its process bundle IDs
/// (`com.microsoft.teams2.modulehost` → Teams).
public struct MeetingApp: Equatable, Hashable, Sendable {
    public let name: String
    /// Browsers hold the mic for many reasons; they only count as a meeting
    /// when the browser also has WebRTC UDP sockets open.
    public let isBrowser: Bool

    public init(name: String, isBrowser: Bool) {
        self.name = name
        self.isBrowser = isBrowser
    }

    /// Stable lowercase id for the note's `platform` field: `teams`, `zoom`,
    /// `facetime`... Browsers are `browser`: the call could be Meet, Teams web
    /// or Zoom web, and the tab isn't knowable from the mic/socket scan.
    public var platform: String { isBrowser ? "browser" : name.lowercased() }
}

public enum MeetingApps {
    /// Bundle ID → app. A prefix matches itself and any `prefix.*` helper.
    private static let natives: [(prefix: String, name: String)] = [
        ("com.microsoft.teams2", "Teams"),
        ("com.microsoft.teams", "Teams"),
        ("us.zoom.xos", "Zoom"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.hnc.Discord", "Discord"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
    ]

    private static let browsers: [(prefix: String, name: String)] = [
        ("com.google.Chrome", "Chrome"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.microsoft.edgemac", "Edge"),
        ("com.brave.Browser", "Brave"),
        ("com.apple.Safari", "Safari"),
        // Safari (and any WKWebView) captures the mic in the WebKit GPU process.
        ("com.apple.WebKit", "Safari"),
        ("org.mozilla.firefox", "Firefox"),
    ]

    public static func classify(bundleID: String) -> MeetingApp? {
        func matches(_ prefix: String) -> Bool {
            bundleID == prefix || bundleID.hasPrefix(prefix + ".")
        }
        if let hit = natives.first(where: { matches($0.prefix) }) {
            return MeetingApp(name: hit.name, isBrowser: false)
        }
        if let hit = browsers.first(where: { matches($0.prefix) }) {
            return MeetingApp(name: hit.name, isBrowser: true)
        }
        return nil
    }

    /// WebRTC ICE sockets are bound but unconnected (no remote port).
    /// Excludes mDNS (5353, Chrome opens it for ICE too but also without a
    /// call) and QUIC, which is connected to the server (remote port 443).
    /// Validated against Chrome 155: no such socket with only getUserMedia +
    /// QUIC tabs; several with an RTCPeerConnection.
    public static func isWebRTCSocket(localPort: UInt16, remotePort: UInt16) -> Bool {
        remotePort == 0 && localPort != 0 && localPort != 5353
    }
}

/// Debounced meeting start/end, fed by periodic snapshots of the apps that
/// hold the mic. Pure: the caller supplies the clock.
///
/// - Start: the same app keeps the mic for `startDelay` (filters a quick
///   mic test / permission probe).
/// - End: the app that started the meeting loses the mic for `endGrace`
///   (mute in some apps, device switch).
///
/// One meeting at a time; `.started` fires once per session, so a declined
/// or ignored prompt is not repeated until the session ends.
public struct MeetingDetection: Sendable {
    public enum Event: Equatable, Sendable {
        case started(MeetingApp)
        case ended(MeetingApp)
    }

    private enum State: Sendable {
        case idle
        case pending(MeetingApp, since: Date)
        case active(MeetingApp, lastSeen: Date)
    }

    public let startDelay: TimeInterval
    public let endGrace: TimeInterval
    private var state: State = .idle

    public init(startDelay: TimeInterval = 3, endGrace: TimeInterval = 20) {
        self.startDelay = startDelay
        self.endGrace = endGrace
    }

    /// The app of the meeting in progress, if any.
    public var activeApp: MeetingApp? {
        if case .active(let app, _) = state { return app }
        return nil
    }

    public mutating func reset() { state = .idle }

    public mutating func tick(now: Date, apps: [MeetingApp]) -> Event? {
        switch state {
        case .idle:
            if let app = apps.first { state = .pending(app, since: now) }
            return nil
        case .pending(let app, let since):
            guard apps.contains(app) else {
                state = apps.first.map { .pending($0, since: now) } ?? .idle
                return nil
            }
            guard now.timeIntervalSince(since) >= startDelay else { return nil }
            state = .active(app, lastSeen: now)
            return .started(app)
        case .active(let app, let lastSeen):
            if apps.contains(app) {
                state = .active(app, lastSeen: now)
                return nil
            }
            guard now.timeIntervalSince(lastSeen) >= endGrace else { return nil }
            state = .idle
            return .ended(app)
        }
    }
}
