import XCTest
@testable import VoiceType

final class AudioInputResolverTests: XCTestCase {

    func testExplicitUIDIsReturnedAsExplicit() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "airpods-uid",
            continuityFallbackEnabled: true,
            isDefaultInputUsable: { XCTFail("must not query default when explicit is set"); return false },
            firstContinuityInputDeviceUID: { XCTFail("must not query continuity when explicit is set"); return nil }
        )
        XCTAssertEqual(result.uid, "airpods-uid")
        XCTAssertEqual(result.source, .explicit)
    }

    func testWhitespaceOnlyExplicitIsTreatedAsEmpty() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "   \n  ",
            continuityFallbackEnabled: true,
            isDefaultInputUsable: { true },
            firstContinuityInputDeviceUID: { "iphone-uid" }
        )
        XCTAssertNil(result.uid)
        XCTAssertEqual(result.source, .systemDefault)
    }

    func testEmptyExplicitWithUsableDefaultReturnsSystemDefault() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "",
            continuityFallbackEnabled: true,
            isDefaultInputUsable: { true },
            firstContinuityInputDeviceUID: { XCTFail("must not query continuity when default is usable"); return nil }
        )
        XCTAssertNil(result.uid)
        XCTAssertEqual(result.source, .systemDefault)
    }

    func testEmptyExplicitUnusableDefaultContinuityAvailableTogglesOn() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "",
            continuityFallbackEnabled: true,
            isDefaultInputUsable: { false },
            firstContinuityInputDeviceUID: { "iphone-uid" }
        )
        XCTAssertEqual(result.uid, "iphone-uid")
        XCTAssertEqual(result.source, .continuityFallback)
    }

    func testEmptyExplicitUnusableDefaultContinuityAvailableButToggleOff() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "",
            continuityFallbackEnabled: false,
            isDefaultInputUsable: { false },
            firstContinuityInputDeviceUID: { XCTFail("toggle off must not query continuity"); return nil }
        )
        XCTAssertNil(result.uid)
        XCTAssertEqual(result.source, .systemDefault)
    }

    func testEmptyExplicitUnusableDefaultNoContinuityAvailable() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "",
            continuityFallbackEnabled: true,
            isDefaultInputUsable: { false },
            firstContinuityInputDeviceUID: { nil }
        )
        XCTAssertNil(result.uid)
        XCTAssertEqual(result.source, .systemDefault)
    }

    // MARK: - Stale USB UID healing

    private let hyperXNew = AudioInputDevice(uniqueID: "USB:HyperX:134000:2,1", localizedName: "HyperX QuadCast S", isContinuity: false)
    private let builtIn = AudioInputDevice(uniqueID: "BuiltInMicrophoneDevice", localizedName: "MacBook Pro Microphone", isContinuity: false)

    func testHealedUIDMatchesSavedNameWhenSavedUIDIsGone() {
        let healed = AudioInputResolver.healedUID(saved: "USB:HyperX:1134000:2,1", label: "HyperX QuadCast S", devices: [builtIn, hyperXNew])
        XCTAssertEqual(healed, hyperXNew.uniqueID)
    }

    func testHealedUIDIsNilWhenSavedUIDStillPresent() {
        XCTAssertNil(AudioInputResolver.healedUID(saved: hyperXNew.uniqueID, label: "HyperX QuadCast S", devices: [hyperXNew]))
    }

    func testHealedUIDIsNilWhenNameIsAmbiguousOrMissing() {
        let twin = AudioInputDevice(uniqueID: "USB:HyperX:other", localizedName: "HyperX QuadCast S", isContinuity: false)
        XCTAssertNil(AudioInputResolver.healedUID(saved: "gone", label: "HyperX QuadCast S", devices: [hyperXNew, twin]))
        XCTAssertNil(AudioInputResolver.healedUID(saved: "gone", label: "Nope", devices: [hyperXNew]))
        XCTAssertNil(AudioInputResolver.healedUID(saved: "gone", label: "", devices: [hyperXNew]))
    }

    func testResolveHealsStaleExplicitUIDByLabel() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "USB:HyperX:1134000:2,1",
            explicitLabel: "HyperX QuadCast S",
            continuityFallbackEnabled: false,
            uidIsPresent: { _ in false },
            currentDevices: { [self.builtIn, self.hyperXNew] }
        )
        XCTAssertEqual(result, .init(uid: hyperXNew.uniqueID, source: .explicit))
    }

    func testResolveSkipsDiscoveryWhenExplicitUIDIsPresent() {
        let result = AudioInputResolver.resolveDeviceUID(
            explicit: "BuiltInMicrophoneDevice",
            explicitLabel: "MacBook Pro Microphone",
            continuityFallbackEnabled: false,
            uidIsPresent: { _ in true },
            currentDevices: { XCTFail("must not enumerate devices when saved UID is live"); return [] }
        )
        XCTAssertEqual(result.uid, "BuiltInMicrophoneDevice")
    }
}
