import CoreAudio
import Foundation

// Thin CoreAudio HAL helpers. No state; safe to call from any thread.
enum AudioDeviceResolver {

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        let ids = allInputDeviceIDs()
        for id in ids where deviceUID(for: id) == uid {
            return id
        }
        return nil
    }

    static func deviceUID(for id: AudioDeviceID) -> String? {
        var uidCF: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &uidCF) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return uidCF as String?
    }

    static func allInputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.filter { hasInputStream($0) }
    }

    private static func hasInputStream(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    static func transportType(for id: AudioDeviceID) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    static func isContinuityDevice(_ id: AudioDeviceID) -> Bool {
        guard let t = transportType(for: id) else { return false }
        return t == kAudioDeviceTransportTypeContinuityCaptureWired
            || t == kAudioDeviceTransportTypeContinuityCaptureWireless
    }

    // Heuristic: a default input is "usable" if it has at least one input stream
    // and reports a positive nominal sample rate. In clamshell without an
    // external mic, the system can fall back to a stale default that fails both.
    static func isDefaultInputUsable() -> Bool {
        guard let id = defaultInputDeviceID() else { return false }
        guard hasInputStream(id) else { return false }
        return sampleRate(for: id).map { $0 > 0 } ?? false
    }

    static func firstContinuityInputDeviceUID() -> String? {
        for id in allInputDeviceIDs() where isContinuityDevice(id) {
            if let uid = deviceUID(for: id) { return uid }
        }
        return nil
    }

    private static func sampleRate(for id: AudioDeviceID) -> Double? {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate)
        guard status == noErr else { return nil }
        return rate
    }
}
