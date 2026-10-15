import Testing
import Core
@testable import VoiceType

@Suite("ShortcutManager.applyConfig")
@MainActor
struct ShortcutManagerTests {

    init() {
        // CGEvent.tapCreate(.cgSessionEventTap, …) returns nil under xctest on
        // macOS 14+ without an Accessibility grant. Without this bypass watch()
        // rolls back the registration and simulateKeyDown finds nothing to fire.
        HoldDetector.skipTapInstall = true
    }

    @Test("press emits .refine when configured globalShortcut keyDown matches")
    func pressEmitsRefine() async throws {
        let store = ConfigStore.inMemory()
        var cfg = try await store.load()
        cfg.shortcuts.refine = "CommandOrControl+Shift+V"
        cfg.translate.enabled = false
        try await store.save(cfg)

        let detector = HoldDetector()
        let manager = ShortcutManager(configStore: store, holdDetector: detector)
        await manager.applyConfig()

        var iter = manager.events.makeAsyncIterator()
        detector.simulateKeyDown(keycode: Keycode.v, flags: [.maskCommand, .maskShift])
        let event = await iter.next()
        #expect(event == .pressed(.refine))
    }

    @Test("release emits .refine when registered keycode goes up after press")
    func releaseEmitsRefine() async throws {
        let store = ConfigStore.inMemory()
        var cfg = try await store.load()
        cfg.shortcuts.refine = "CommandOrControl+Shift+V"
        cfg.translate.enabled = false
        cfg.handsFreeEnabled = false  // a quick tap would open the double-tap window
        try await store.save(cfg)

        let detector = HoldDetector()
        let manager = ShortcutManager(configStore: store, holdDetector: detector)
        await manager.applyConfig()

        var iter = manager.events.makeAsyncIterator()
        // onRelease only fires after the registration has been activated by a
        // matching keyDown — otherwise a solo keypress of the main key would
        // emit spurious .refine events (and the macOS Press-and-Hold accent
        // picker would steal the keyUp).
        detector.simulateKeyDown(keycode: Keycode.v, flags: [.maskCommand, .maskShift])
        detector.simulateKeyUp(keycode: Keycode.v)
        #expect(await iter.next() == .pressed(.refine))
        #expect(await iter.next() == .released(.refine))
    }

    @Test("translate registration only when translateEnabled")
    func translateRegistersOnlyWhenEnabled() async throws {
        let store = ConfigStore.inMemory()
        var cfg = try await store.load()
        cfg.shortcuts.refine = "CommandOrControl+Shift+V"
        cfg.translate.enabled = true
        cfg.shortcuts.translate = "CommandOrControl+Shift+E"
        try await store.save(cfg)

        let detector = HoldDetector()
        let manager = ShortcutManager(configStore: store, holdDetector: detector)
        await manager.applyConfig()

        var iter = manager.events.makeAsyncIterator()
        detector.simulateKeyDown(keycode: Keycode.e, flags: [.maskCommand, .maskShift])
        let event = await iter.next()
        #expect(event == .pressed(.translate))
    }

    @Test("translate disabled → no fire on translate keycode")
    func translateDisabledNoFire() async throws {
        let store = ConfigStore.inMemory()
        var cfg = try await store.load()
        cfg.shortcuts.refine = "CommandOrControl+Shift+V"
        cfg.translate.enabled = false
        cfg.shortcuts.translate = "CommandOrControl+Shift+E"
        try await store.save(cfg)

        let detector = HoldDetector()
        let manager = ShortcutManager(configStore: store, holdDetector: detector)
        await manager.applyConfig()

        // Press translate combo — should NOT yield. Press refine after to confirm
        // the stream is alive and only refine arrives.
        detector.simulateKeyDown(keycode: Keycode.e, flags: [.maskCommand, .maskShift])
        detector.simulateKeyDown(keycode: Keycode.v, flags: [.maskCommand, .maskShift])

        var iter = manager.events.makeAsyncIterator()
        let first = await iter.next()
        #expect(first == .pressed(.refine))
    }

    @Test("extra key right after press emits .cancelled and is not swallowed")
    func extraKeyEmitsCancelled() async throws {
        let store = ConfigStore.inMemory()
        var cfg = try await store.load()
        cfg.shortcuts.refine = "CommandOrControl+Shift+V"
        cfg.translate.enabled = false
        try await store.save(cfg)

        let detector = HoldDetector()
        let manager = ShortcutManager(configStore: store, holdDetector: detector)
        await manager.applyConfig()

        var iter = manager.events.makeAsyncIterator()
        detector.simulateKeyDown(keycode: Keycode.v, flags: [.maskCommand, .maskShift])
        let swallowed = detector.simulateKeyDown(keycode: Keycode.a, flags: [.maskCommand, .maskShift])
        #expect(swallowed == false)
        #expect(await iter.next() == .pressed(.refine))
        #expect(await iter.next() == .cancelled(.refine))
    }

    @Test("modifier-only Fn shortcut emits press/release from flagsChanged")
    func fnShortcutFromFlagsChanged() async throws {
        let store = ConfigStore.inMemory()
        var cfg = try await store.load()
        cfg.shortcuts.refine = "Fn"
        cfg.translate.enabled = false
        cfg.handsFreeEnabled = false
        try await store.save(cfg)

        let detector = HoldDetector()
        let manager = ShortcutManager(configStore: store, holdDetector: detector)
        await manager.applyConfig()

        var iter = manager.events.makeAsyncIterator()
        detector.simulateFlagsChanged(keycode: Keycode.fn, flags: .maskSecondaryFn)
        detector.simulateFlagsChanged(keycode: Keycode.fn, flags: [])
        #expect(await iter.next() == .pressed(.refine))
        #expect(await iter.next() == .released(.refine))
    }
}
