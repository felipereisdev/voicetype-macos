// Ports src/main/hold-detector.test.ts to swift-testing.
//
// Translation deltas from the Phase 4 plan:
// - Plan test 11 ("returns error when uIOhook.start throws") moved out of core
//   coverage — that failure is wrapper-only (CGEventTap install) and would
//   require entitlements-granted CI to exercise. Documented as a Phase 6 follow-up.
// - All `vi.fn()` spies become `var calls = 0` closures.
// - All `uIOhook.on/start/stop` mock assertions collapse into assertions on
//   `core.registrations` and the `unwatch()` teardown bool.

import Testing
import CoreGraphics
import Foundation
@testable import VoiceType

@Suite("parseAccelerator")
struct ParseAcceleratorTests {

    @Test func parsesCommandOrControlShiftV() throws {
        let result = HoldDetectorCore.parseAccelerator("CommandOrControl+Shift+V")
        let codes = try #require(result.keycodes)
        #expect(codes == Set([Keycode.meta, Keycode.shift, Keycode.v]))
    }

    @Test func parsesCmdSpace() throws {
        let result = HoldDetectorCore.parseAccelerator("Cmd+Space")
        let codes = try #require(result.keycodes)
        #expect(codes == Set([Keycode.meta, Keycode.space]))
    }

    @Test func parsesAltF1() throws {
        let result = HoldDetectorCore.parseAccelerator("Alt+F1")
        let codes = try #require(result.keycodes)
        #expect(codes == Set([Keycode.alt, Keycode.f1]))
    }

    @Test func returnsErrorForUnknownToken() {
        let result = HoldDetectorCore.parseAccelerator("CommandOrControl+Shift+SomeWeirdKey")
        #expect(result.keycodes == nil)
        #expect(result.error?.contains("SomeWeirdKey") == true)
    }

    @Test func returnsErrorOnEmptyInput() {
        #expect(HoldDetectorCore.parseAccelerator("").keycodes == nil)
    }
}

@Suite("createHoldDetector")
struct CreateHoldDetectorTests {

    @Test func registersWatch() {
        var core = HoldDetectorCore()
        let result = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: {})
        #expect(result.ok)
        #expect(core.registrations.count == 1)
        #expect(core.registrations["CommandOrControl+Shift+V"]?.keycodes ==
                Set([Keycode.meta, Keycode.shift, Keycode.v]))
    }

    @Test func firesOnReleaseAfterPressOfMainKeyWithModifiers() {
        var core = HoldDetectorCore()
        var releases = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: { releases += 1 })

        let flags: CGEventFlags = [.maskCommand, .maskShift]
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        core.dispatchKeyUp(keycode: Keycode.v)
        #expect(releases == 1)

        // Releasing an unrelated key after the shortcut cycle is a no-op.
        core.dispatchKeyUp(keycode: Keycode.a)
        #expect(releases == 1)
    }

    // Regression: typing the shortcut's main key SOLO (without modifiers) must
    // not consume the keyUp. Previously, dispatchKeyUp fired onRelease + returned
    // true for any keycode matching a registration's main key, causing the
    // focused app to see a keyDown without a paired keyUp. After ~400ms macOS
    // would trigger the Press-and-Hold accent picker on letters like n, a, e.
    @Test func soloLetterTapDoesNotConsumeOrFire() {
        var core = HoldDetectorCore()
        var releases = 0
        var presses = 0
        _ = core.watch(
            "CommandOrControl+Shift+Z",
            onPress: { presses += 1 },
            onRelease: { releases += 1 }
        )

        let downConsumed = core.dispatchKeyDown(keycode: Keycode.z, flags: [])
        let upConsumed = core.dispatchKeyUp(keycode: Keycode.z)

        #expect(downConsumed == false)
        #expect(upConsumed == false)
        #expect(presses == 0)
        #expect(releases == 0)
    }

    // Releasing a modifier of an active shortcut (push-to-talk: release Shift
    // while still holding Cmd + main key) ends recording. The keyUp itself is
    // NOT swallowed because flagsChanged events always propagate so the OS
    // keeps modifier state in sync with the focused app.
    @Test func modifierReleaseFiresOnReleaseButPropagates() {
        var core = HoldDetectorCore()
        var releases = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: { releases += 1 })

        let flags: CGEventFlags = [.maskCommand, .maskShift]
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        let upConsumed = core.dispatchKeyUp(keycode: Keycode.shift)
        #expect(releases == 1)
        #expect(upConsumed == false)
    }

    // Auto-repeating keyDowns (system fires keyDown while shortcut still held)
    // must keep swallowing the event so terminals don't see auto-repeated main
    // key chars, but onPress fires only on the leading edge.
    @Test func autoRepeatDoesNotRefireOnPressButKeepsSwallowing() {
        var core = HoldDetectorCore()
        var presses = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: { presses += 1 }, onRelease: {})

        let flags: CGEventFlags = [.maskCommand, .maskShift]
        let first = core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        let repeated = core.dispatchKeyDown(keycode: Keycode.v, flags: flags)

        #expect(first == true)
        #expect(repeated == true)
        #expect(presses == 1)
    }

    @Test func firesOnPressWhenAllModifiersAndMainKeyMatch() {
        var core = HoldDetectorCore()
        var presses = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: { presses += 1 }, onRelease: {})

        let flags: CGEventFlags = [.maskCommand, .maskShift]
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        #expect(presses == 1)

        // Missing Shift → no fire.
        core.dispatchKeyDown(keycode: Keycode.v, flags: [.maskCommand])
        #expect(presses == 1)

        // Wrong main key → no fire.
        core.dispatchKeyDown(keycode: Keycode.a, flags: flags)
        #expect(presses == 1)
    }

    @Test func returnsErrorForInvalidAccelerator() {
        var core = HoldDetectorCore()
        let result = core.watch("NotARealKey", onPress: {}, onRelease: {})
        #expect(result.ok == false)
    }

    @Test func unwatchClearsAllRegistrations() {
        var core = HoldDetectorCore()
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: {})
        let shouldTeardown = core.unwatch()
        #expect(shouldTeardown)
        #expect(core.registrations.isEmpty)
    }

    @Test func watchesTwoDistinctAcceleratorsAndDispatchesIndependently() {
        var core = HoldDetectorCore()
        var aReleases = 0, bReleases = 0
        let r1 = core.watch("CommandOrControl+Shift+Space", onPress: {}, onRelease: { aReleases += 1 })
        #expect(r1.ok)
        let r2 = core.watch("CommandOrControl+Shift+E", onPress: {}, onRelease: { bReleases += 1 })
        #expect(r2.ok)

        let flags: CGEventFlags = [.maskCommand, .maskShift]

        core.dispatchKeyDown(keycode: Keycode.space, flags: flags)
        core.dispatchKeyUp(keycode: Keycode.space)
        #expect(aReleases == 1)
        #expect(bReleases == 0)

        core.dispatchKeyDown(keycode: Keycode.e, flags: flags)
        core.dispatchKeyUp(keycode: Keycode.e)
        #expect(bReleases == 1)
        #expect(aReleases == 1)

        _ = core.unwatch()
    }

    @Test func unwatchAcceleratorRemovesOneRegistrationKeepsTap() {
        var core = HoldDetectorCore()
        _ = core.watch("CommandOrControl+Shift+Space", onPress: {}, onRelease: {})
        _ = core.watch("CommandOrControl+Shift+E", onPress: {}, onRelease: {})

        let shouldTeardown = core.unwatch("CommandOrControl+Shift+Space")
        #expect(shouldTeardown == false)
        #expect(core.registrations.count == 1)

        let finalTeardown = core.unwatch()
        #expect(finalTeardown)
    }

    @Test func unwatchWithNoArgClearsAllAndSignalsTeardown() {
        var core = HoldDetectorCore()
        _ = core.watch("CommandOrControl+Shift+Space", onPress: {}, onRelease: {})
        _ = core.watch("CommandOrControl+Shift+E", onPress: {}, onRelease: {})
        let teardown = core.unwatch()
        #expect(teardown)
    }
}

final class FakeClock {
    var now: TimeInterval = 0
}

@Suite("cancel window (shortcut used as modifier)")
struct CancelWindowTests {

    private let flags: CGEventFlags = [.maskCommand, .maskShift]

    private func makeCore(_ clock: FakeClock) -> HoldDetectorCore {
        HoldDetectorCore(clock: { clock.now })
    }

    @Test func extraKeyInsideWindowCancelsAndPassesThrough() {
        let clock = FakeClock()
        var core = makeCore(clock)
        var presses = 0, releases = 0, cancels = 0
        _ = core.watch("CommandOrControl+Shift+V",
                       onPress: { presses += 1 }, onRelease: { releases += 1 }, onCancel: { cancels += 1 })

        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 0.999
        let extraSwallowed = core.dispatchKeyDown(keycode: Keycode.a, flags: flags)
        #expect(extraSwallowed == false)
        #expect(cancels == 1)

        // Main key still held: auto-repeat stays swallowed but doesn't restart.
        #expect(core.dispatchKeyDown(keycode: Keycode.v, flags: flags) == true)
        #expect(presses == 1)

        // Releasing the chord neither fires release nor leaks the main keyUp.
        #expect(core.dispatchKeyUp(keycode: Keycode.v) == true)
        #expect(core.dispatchKeyUp(keycode: Keycode.a) == false)
        #expect(releases == 0)

        // Next clean press works again.
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        #expect(presses == 2)
    }

    @Test func extraKeyAfterWindowIsIgnored() {
        let clock = FakeClock()
        var core = makeCore(clock)
        var releases = 0, cancels = 0
        _ = core.watch("CommandOrControl+Shift+V",
                       onPress: {}, onRelease: { releases += 1 }, onCancel: { cancels += 1 })

        clock.now = 10
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 11
        #expect(core.dispatchKeyDown(keycode: Keycode.a, flags: flags) == false)
        #expect(cancels == 0)

        core.dispatchKeyUp(keycode: Keycode.v)
        #expect(releases == 1)
    }

    @Test func windowIsConfigurable() {
        let clock = FakeClock()
        var core = makeCore(clock)
        core.cancelWindow = 0.25
        var cancels = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: {}, onCancel: { cancels += 1 })

        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 0.3
        core.dispatchKeyDown(keycode: Keycode.a, flags: flags)
        #expect(cancels == 0)
    }

    @Test func autoRepeatOfMainKeyDoesNotCancel() {
        let clock = FakeClock()
        var core = makeCore(clock)
        var cancels = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: {}, onCancel: { cancels += 1 })

        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 0.5
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        #expect(cancels == 0)
    }
}

@Suite("reconcile (lost keyUps after tap disabled)")
struct ReconcileTests {

    private let flags: CGEventFlags = [.maskCommand, .maskShift]

    @Test func activeShortcutWithReleasedKeyEndsAsNormalRelease() {
        var core = HoldDetectorCore()
        var releases = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: { releases += 1 })
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)

        // Tap blind: V's keyUp never arrived. Live state says only Cmd held.
        core.reconcile(isDown: { $0 == Keycode.meta })
        #expect(releases == 1)

        // Late keyUp neither re-fires nor leaks to the app as a stray keyUp.
        #expect(core.dispatchKeyUp(keycode: Keycode.v) == false)
        #expect(releases == 1)
    }

    @Test func stillHeldShortcutKeepsRecording() {
        var core = HoldDetectorCore()
        var releases = 0
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: { releases += 1 })
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)

        core.reconcile(isDown: { _ in true })
        #expect(releases == 0)
        // Swallow-pending keyUp is kept for the real release.
        #expect(core.dispatchKeyUp(keycode: Keycode.v) == true)
        #expect(releases == 1)
    }

    @Test func phantomKeysOutsideRecordingAreDropped() {
        let clock = FakeClock()
        var core = HoldDetectorCore(clock: { clock.now })
        var presses = 0, cancels = 0
        _ = core.watch("CommandOrControl+Shift+V",
                       onPress: { presses += 1 }, onRelease: {}, onCancel: { cancels += 1 })
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        core.dispatchKeyDown(keycode: Keycode.a, flags: flags)  // cancel → suppressed
        #expect(cancels == 1)

        core.reconcile(isDown: { _ in false })

        // Nothing stuck: suppression lifted, no pending swallow, next press fires.
        #expect(core.dispatchKeyUp(keycode: Keycode.v) == false)
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        #expect(presses == 2)
    }

    @Test func idleCoreDoesNotQueryKeyState() {
        var core = HoldDetectorCore()
        _ = core.watch("CommandOrControl+Shift+V", onPress: {}, onRelease: {})
        var queries = 0
        core.reconcile(isDown: { _ in queries += 1; return false })
        #expect(queries == 0)
    }
}

@Suite("TapStormGuard")
struct TapStormGuardTests {

    @Test func fifthReenableInsideWindowRecreates() {
        var guardian = TapStormGuard()
        let verdicts = [100.0, 101, 102, 103, 104].map { guardian.shouldRecreate(at: $0) }
        #expect(verdicts == [false, false, false, false, true])
        // Counter resets after a recreate.
        #expect(guardian.shouldRecreate(at: 104.5) == false)
    }

    @Test func reenablesSpreadBeyondWindowNeverRecreate() {
        var guardian = TapStormGuard()
        for t in stride(from: 100.0, through: 200, by: 2.5) {
            #expect(guardian.shouldRecreate(at: t) == false)
        }
    }

    @Test func wakeGraceExcludesReenables() {
        var guardian = TapStormGuard()
        guardian.noteWake(at: 1000)
        for t in stride(from: 1000.0, to: 1059, by: 0.5) {
            #expect(guardian.shouldRecreate(at: t) == false)
        }
        // After the grace period counting resumes.
        let verdicts = [1061.0, 1062, 1063, 1064, 1065].map { guardian.shouldRecreate(at: $0) }
        #expect(verdicts.last == true)
    }
}

@Suite("hands-free gestures")
struct HandsFreeTests {

    final class Spy {
        var log: [String] = []
    }

    private let flags: CGEventFlags = [.maskCommand, .maskShift]
    private let accel = "CommandOrControl+Shift+V"

    private func makeCore(_ clock: FakeClock, _ spy: Spy, handsFree: Bool = true) -> HoldDetectorCore {
        var core = HoldDetectorCore(clock: { clock.now })
        core.handsFreeEnabled = handsFree
        core.upgradeKeycode = Keycode.space
        _ = core.watch(accel,
                       onPress: { spy.log.append("press") },
                       onRelease: { spy.log.append("release") },
                       onCancel: { spy.log.append("cancel") },
                       onLock: { spy.log.append("lock") })
        return core
    }

    private func tap(_ core: inout HoldDetectorCore, _ clock: FakeClock, at t: TimeInterval, hold: TimeInterval) {
        clock.now = t
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = t + hold
        core.dispatchKeyUp(keycode: Keycode.v)
    }

    // Recording cap (5 min) ends the take through the normal release path.
    @Test func forceReleaseWhileHoldingEndsTakeUntilKeyUp() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        clock.now = 0
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 300
        core.forceRelease()
        #expect(spy.log == ["press", "release"])
        // Still held: auto-repeat must not start a new take; the late keyUp is spent.
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        core.dispatchKeyUp(keycode: Keycode.v)
        #expect(spy.log == ["press", "release"])
        // Next clean press records again.
        tap(&core, clock, at: 301, hold: 1)
        #expect(spy.log == ["press", "release", "press", "release"])
    }

    // Modifier released first, re-pressed while the main key still repeats:
    // the chord stays spent until the main key's own keyUp.
    @Test func forceReleaseModifierFirstReleaseDoesNotRearm() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        clock.now = 0
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 300
        core.forceRelease()
        core.dispatchFlagsChanged(keycode: Keycode.shift, flags: [.maskCommand])
        core.dispatchFlagsChanged(keycode: Keycode.shift, flags: flags)
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        #expect(spy.log == ["press", "release"])
    }

    // Config save mid-take re-registers shortcuts: the active one must release.
    @Test func unwatchReleasesActiveGesture() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        clock.now = 0
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        core.unwatch()
        #expect(spy.log == ["press", "release"])
    }

    @Test func forceReleaseWhileLockedRearmsNextTap() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        tap(&core, clock, at: 0, hold: 0.1)
        tap(&core, clock, at: 0.3, hold: 0.1)
        core.forceRelease()
        #expect(spy.log == ["press", "lock", "release"])
        clock.now = 301
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        #expect(spy.log == ["press", "lock", "release", "press"])
    }

    @Test func disabledKeepsPushToTalk() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy, handsFree: false)
        tap(&core, clock, at: 0, hold: 0.1)
        tap(&core, clock, at: 0.2, hold: 0.1)
        #expect(spy.log == ["press", "release", "press", "release"])
        #expect(core.pendingDeadline == nil)
    }

    @Test func longHoldIsStillPushToTalk() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        tap(&core, clock, at: 0, hold: 0.5)  // exactly the window → PTT
        #expect(spy.log == ["press", "release"])
    }

    @Test func holdJustUnderWindowAwaitsSecondTap() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        tap(&core, clock, at: 0, hold: 0.499)
        #expect(spy.log == ["press"])
        #expect(core.pendingDeadline == 0.999)
    }

    @Test func doubleTapLocksThenThirdTapStopsAndPastes() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        tap(&core, clock, at: 0, hold: 0.1)
        tap(&core, clock, at: 0.3, hold: 0.1)
        #expect(spy.log == ["press", "lock"])
        #expect(core.pendingDeadline == nil)

        // Locked: keys are up, extra keys don't cancel, timeout doesn't fire.
        clock.now = 5
        core.dispatchKeyDown(keycode: Keycode.a, flags: [])
        core.expirePending()
        #expect(spy.log == ["press", "lock"])

        tap(&core, clock, at: 10, hold: 0.1)
        #expect(spy.log == ["press", "lock", "release"])

        // Back to idle: a fresh press starts a new take.
        tap(&core, clock, at: 20, hold: 1)
        #expect(spy.log == ["press", "lock", "release", "press", "release"])
    }

    @Test func secondTapAtWindowBoundaries() {
        // 499 ms after release → lock; 500 / 501 ms → first take discarded,
        // the late tap starts a new one.
        for (gap, expected) in [(0.499, ["press", "lock"]),
                                (0.5, ["press", "cancel", "press"]),
                                (0.501, ["press", "cancel", "press"])] {
            let clock = FakeClock(), spy = Spy()
            var core = makeCore(clock, spy)
            tap(&core, clock, at: 0, hold: 0.1)
            clock.now = 0.1 + gap
            core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
            #expect(spy.log == expected, "gap \(gap)")
        }
    }

    @Test func isolatedShortTapIsDiscardedOnTimeout() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        tap(&core, clock, at: 0, hold: 0.1)
        clock.now = 0.599
        core.expirePending()
        #expect(spy.log == ["press"])
        clock.now = 0.6
        core.expirePending()
        #expect(spy.log == ["press", "cancel"])
        #expect(core.pendingDeadline == nil)
    }

    @Test func escCancelsLockedTakeAndIsSwallowed() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        tap(&core, clock, at: 0, hold: 0.1)
        tap(&core, clock, at: 0.3, hold: 0.1)
        clock.now = 3
        #expect(core.dispatchKeyDown(keycode: Keycode.escape, flags: []) == true)
        #expect(core.dispatchKeyUp(keycode: Keycode.escape) == true)
        #expect(spy.log == ["press", "lock", "cancel"])
    }

    @Test func escOutsideHandsFreePassesThrough() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        #expect(core.dispatchKeyDown(keycode: Keycode.escape, flags: []) == false)
        #expect(spy.log.isEmpty)
    }

    @Test func upgradeKeyWhileHoldingLocksWithoutRestart() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 0.2  // inside the cancel window: upgrade key is exempt
        #expect(core.dispatchKeyDown(keycode: Keycode.space, flags: flags) == true)
        #expect(core.dispatchKeyUp(keycode: Keycode.space) == true)
        clock.now = 0.3
        core.dispatchKeyUp(keycode: Keycode.v)
        #expect(spy.log == ["press", "lock"])  // same take, no stop/restart

        tap(&core, clock, at: 4, hold: 0.1)
        #expect(spy.log == ["press", "lock", "release"])
    }

    @Test func upgradeKeyIgnoredWhenHandsFreeDisabled() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy, handsFree: false)
        core.dispatchKeyDown(keycode: Keycode.v, flags: flags)
        clock.now = 0.2
        #expect(core.dispatchKeyDown(keycode: Keycode.space, flags: flags) == false)
        #expect(spy.log == ["press", "cancel"])  // #47 rule applies instead
    }

    @Test func reconcileLeavesHandsFreeTakeAlone() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore(clock, spy)
        tap(&core, clock, at: 0, hold: 0.1)
        tap(&core, clock, at: 0.3, hold: 0.1)
        core.reconcile(isDown: { _ in false })  // keys up on purpose
        #expect(spy.log == ["press", "lock"])
    }
}

@Suite("modifier-only shortcuts (Fn / Control+Alt)")
struct ModifierOnlyTests {

    final class Spy {
        var log: [String] = []
    }

    private func makeCore(_ accel: String, _ clock: FakeClock, _ spy: Spy, handsFree: Bool = false) -> HoldDetectorCore {
        var core = HoldDetectorCore(clock: { clock.now })
        core.handsFreeEnabled = handsFree
        let result = core.watch(accel,
                                onPress: { spy.log.append("press") },
                                onRelease: { spy.log.append("release") },
                                onCancel: { spy.log.append("cancel") },
                                onLock: { spy.log.append("lock") })
        #expect(result.ok)
        return core
    }

    @Test func parsesFnAndGlobe() {
        #expect(HoldDetectorCore.parseAccelerator("Fn").keycodes == [Keycode.fn])
        #expect(HoldDetectorCore.parseAccelerator("Globe").keycodes == [Keycode.fn])
        #expect(HoldDetectorCore.parseAccelerator("Control+Alt").keycodes == [Keycode.control, Keycode.alt])
    }

    @Test func fnHoldIsPushToTalk() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("Fn", clock, spy)
        core.dispatchFlagsChanged(keycode: Keycode.fn, flags: .maskSecondaryFn)
        clock.now = 2
        core.dispatchFlagsChanged(keycode: Keycode.fn, flags: [])
        #expect(spy.log == ["press", "release"])
    }

    @Test func globeKeycodeCountsAsFn() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("Fn", clock, spy)
        core.dispatchFlagsChanged(keycode: Keycode.globe, flags: .maskSecondaryFn)
        clock.now = 2
        core.dispatchFlagsChanged(keycode: Keycode.globe, flags: [])
        #expect(spy.log == ["press", "release"])
    }

    @Test func controlAltNeedsTheExactSetAndAcceptsRightHandKeys() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("Control+Alt", clock, spy)
        core.dispatchFlagsChanged(keycode: Keycode.control, flags: .maskControl)
        #expect(spy.log.isEmpty)
        core.dispatchFlagsChanged(keycode: Keycode.rightOption, flags: [.maskControl, .maskAlternate])
        #expect(spy.log == ["press"])
        clock.now = 2
        core.dispatchFlagsChanged(keycode: Keycode.rightOption, flags: .maskControl)
        #expect(spy.log == ["press", "release"])
    }

    @Test func supersetOfModifiersDoesNotFire() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("Control+Alt", clock, spy)
        core.dispatchFlagsChanged(keycode: Keycode.meta, flags: .maskCommand)
        core.dispatchFlagsChanged(keycode: Keycode.control, flags: [.maskCommand, .maskControl])
        core.dispatchFlagsChanged(keycode: Keycode.alt, flags: [.maskCommand, .maskControl, .maskAlternate])
        #expect(spy.log.isEmpty)
    }

    @Test func fnPlusKeyInsideWindowCancelsAndKeyPassesThrough() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("Fn", clock, spy)
        core.dispatchFlagsChanged(keycode: Keycode.fn, flags: .maskSecondaryFn)
        clock.now = 0.2
        // Fn+Delete (forward delete) — the app must still get the key.
        #expect(core.dispatchKeyDown(keycode: Keycode.backspace, flags: .maskSecondaryFn) == false)
        #expect(core.dispatchKeyUp(keycode: Keycode.backspace) == false)
        core.dispatchFlagsChanged(keycode: Keycode.fn, flags: [])
        #expect(spy.log == ["press", "cancel"])
    }

    @Test func extraModifierInsideWindowCancels() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("Control+Alt", clock, spy)
        core.dispatchFlagsChanged(keycode: Keycode.control, flags: .maskControl)
        core.dispatchFlagsChanged(keycode: Keycode.alt, flags: [.maskControl, .maskAlternate])
        clock.now = 0.3
        core.dispatchFlagsChanged(keycode: Keycode.meta, flags: [.maskControl, .maskAlternate, .maskCommand])
        // Releasing the extra modifier must not re-arm while the chord is held.
        core.dispatchFlagsChanged(keycode: Keycode.meta, flags: [.maskControl, .maskAlternate])
        core.dispatchFlagsChanged(keycode: Keycode.alt, flags: .maskControl)
        #expect(spy.log == ["press", "cancel"])
    }

    @Test func fnDoubleTapLocksHandsFree() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("Fn", clock, spy, handsFree: true)
        for t in [0.0, 0.3] {
            clock.now = t
            core.dispatchFlagsChanged(keycode: Keycode.fn, flags: .maskSecondaryFn)
            clock.now = t + 0.1
            core.dispatchFlagsChanged(keycode: Keycode.fn, flags: [])
        }
        #expect(spy.log == ["press", "lock"])
        clock.now = 5
        core.dispatchFlagsChanged(keycode: Keycode.fn, flags: .maskSecondaryFn)
        core.dispatchFlagsChanged(keycode: Keycode.fn, flags: [])
        #expect(spy.log == ["press", "lock", "release"])
    }

    @Test func chordedShortcutStillReleasesOnModifierUp() {
        let clock = FakeClock(), spy = Spy()
        var core = makeCore("CommandOrControl+Shift+V", clock, spy)
        core.dispatchKeyDown(keycode: Keycode.v, flags: [.maskCommand, .maskShift])
        clock.now = 2
        core.dispatchFlagsChanged(keycode: Keycode.rightShift, flags: .maskCommand)
        #expect(spy.log == ["press", "release"])
    }
}

@Test("shortcut overlap: equal, contained or aliased keys conflict")
func shortcutOverlap() {
    #expect(ShortcutsSection.overlaps("Control+Shift", "Control+Shift+N"))
    #expect(ShortcutsSection.overlaps("CommandOrControl+L", "Command+Shift+L"))
    #expect(ShortcutsSection.overlaps("Alt+N", "Option+N"))
    #expect(!ShortcutsSection.overlaps("Control+Shift", "Alt+N"))
    #expect(!ShortcutsSection.overlaps("", "Alt+N"))
}
