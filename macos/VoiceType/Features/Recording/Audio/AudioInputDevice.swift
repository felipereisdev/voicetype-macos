import AVFoundation
import Foundation

struct AudioInputDevice: Equatable, Sendable, Identifiable {
    var id: String { uniqueID }
    let uniqueID: String
    let localizedName: String
    let isContinuity: Bool
}

protocol AudioDeviceProbing: Sendable {
    func discover() -> [AudioInputDevice]
}

struct LiveAudioDeviceProbe: AudioDeviceProbing {
    func discover() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        // Hide CoreAudio's private per-process aggregate ("CADefaultDeviceAggregate-<pid>-N"),
        // created while our own engine/player runs — not a real mic, and its UID dies with the process.
        return session.devices
            .filter { !$0.localizedName.hasPrefix("CADefaultDeviceAggregate") }
            .filter { !$0.uniqueID.hasPrefix(SystemAudioCapture.aggregateUIDPrefix) }
            .map { device in
                // Bridge AVCaptureDevice.uniqueID into the HAL world so we can read
                // transport type. Continuity devices come through AVCapture but the
                // Continuity flag only lives on the CoreAudio side.
                let isContinuity: Bool = {
                    guard let id = AudioDeviceResolver.deviceID(forUID: device.uniqueID) else { return false }
                    return AudioDeviceResolver.isContinuityDevice(id)
                }()
                return AudioInputDevice(
                    uniqueID: device.uniqueID,
                    localizedName: device.localizedName,
                    isContinuity: isContinuity
                )
            }
    }
}
