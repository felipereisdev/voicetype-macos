import Foundation

// Resolves which input device UID the recorder should target before each
// capture. Centralised so it can be unit-tested without real CoreAudio HAL.
enum AudioInputResolver {

    struct Resolved: Equatable, Sendable {
        let uid: String?
        let source: Source
    }

    enum Source: String, Sendable {
        case explicit, systemDefault, continuityFallback
    }

    // Priority: explicit user choice → Continuity fallback (if default unusable
    // and toggle on) → nil (use system default).
    static func resolveDeviceUID(
        explicit: String,
        explicitLabel: String = "",
        continuityFallbackEnabled: Bool,
        isDefaultInputUsable: () -> Bool = AudioDeviceResolver.isDefaultInputUsable,
        firstContinuityInputDeviceUID: () -> String? = AudioDeviceResolver.firstContinuityInputDeviceUID,
        uidIsPresent: (String) -> Bool = { AudioDeviceResolver.deviceID(forUID: $0) != nil },
        currentDevices: () -> [AudioInputDevice] = { LiveAudioDeviceProbe().discover() }
    ) -> Resolved {
        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard !explicitLabel.isEmpty, !uidIsPresent(trimmed),
                  let healed = healedUID(saved: trimmed, label: explicitLabel, devices: currentDevices())
            else { return Resolved(uid: trimmed, source: .explicit) }
            return Resolved(uid: healed, source: .explicit)
        }
        guard continuityFallbackEnabled,
              !isDefaultInputUsable(),
              let continuity = firstContinuityInputDeviceUID() else {
            return Resolved(uid: nil, source: .systemDefault)
        }
        return Resolved(uid: continuity, source: .continuityFallback)
    }

    // USB UIDs embed the port's location ID, so the same mic plugged into
    // another port/hub comes back with a new UID and the saved one matches
    // nothing (recorder silently fell back to the default; Settings showed no
    // selection). Saved UID gone → match the saved name, if exactly one device
    // has it. Returns nil when there's nothing better than the saved UID.
    static func healedUID(saved: String, label: String, devices: [AudioInputDevice]) -> String? {
        guard !label.isEmpty, !devices.contains(where: { $0.uniqueID == saved }) else { return nil }
        let matches = devices.filter { $0.localizedName == label }
        return matches.count == 1 ? matches[0].uniqueID : nil
    }
}
