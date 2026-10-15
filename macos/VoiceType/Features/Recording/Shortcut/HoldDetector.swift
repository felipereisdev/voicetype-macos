import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

// CGEventTap on kCGSessionEventTap listening for keyDown / keyUp / flagsChanged.
// Delegates the decision-making to HoldDetectorCore.
//
// NOT @MainActor: the CGEventTap C-callback runs from CFRunLoopGetMain() and
// enters Swift via a CGEventTapCallBack function pointer. From that context
// `MainActor.assumeIsolated` causes a SIGSEGV on macOS 14+ because the Swift
// runtime's executor-identity check (`swift_task_isCurrentExecutorWithFlags`)
// dereferences task-local state that doesn't exist for a raw C callback —
// even though physically we ARE on the main thread. A lock-protected
// non-isolated class lets the callback read state without involving actor
// machinery. Public API still happens from main-thread callers (ShortcutManager
// is @MainActor), and the callback is invoked by the main runloop, so all
// accesses serialize on the main thread; the lock is belt-and-braces.
final class HoldDetector: @unchecked Sendable {

    private let logger = Logger(subsystem: "VoiceType", category: "HoldDetector")
    private let lock = NSLock()
    private var core: HoldDetectorCore
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sweepTimer: Timer?
    /// A keyUp lost while the tap was blind leaves a recording stuck; the
    /// sweep reconciles the core against the live key state this often. The
    /// same tick is the tap watchdog and the secure-input probe.
    static let sweepInterval: TimeInterval = 5
    private var stormGuard = TapStormGuard()
    private var wakeObserver: NSObjectProtocol?
    private var secureInputWasOn = false
    /// Fired (main thread) when Secure Event Input turns on: the tap sees no
    /// keys until it's off. Arg = owning app name, when macOS exposes it.
    var onSecureInputEnabled: (@Sendable (_ ownerApp: String?) -> Void)?
    /// Without Accessibility the tap can't be created. Registrations stay and
    /// this timer polls `AXIsProcessTrusted()` until the grant lands, then
    /// installs the tap hot — no app relaunch (Wispr Flow does the same).
    private var accessibilityPollTimer: Timer?
    /// Fired (main thread) when a pending tap got installed after the grant.
    var onAccessibilityGranted: (@Sendable () -> Void)?

    init() {
        self.core = HoldDetectorCore()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    @discardableResult
    func watch(
        _ accelerator: String,
        onPress: @escaping @Sendable () -> Void,
        onRelease: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void = {},
        onLock: @escaping @Sendable () -> Void = {}
    ) -> HoldDetectorCore.WatchResult {
        lock.lock()
        let result = core.watch(
            accelerator, onPress: onPress, onRelease: onRelease, onCancel: onCancel, onLock: onLock
        )
        lock.unlock()
        guard result.ok else { return result }
        if tap == nil && !Self.skipTapInstall && !installTap() {
            // Registration kept: the tap goes in once Accessibility is granted.
            startAccessibilityPolling()
            return .failure("tap-install-pending")
        }
        return .success
    }

    /// Test seam — set to `true` from unit tests before constructing a
    /// HoldDetector to bypass `installTap()`. Without this, tests would either
    /// (a) need a real Accessibility grant on the xctest runner or (b) silently
    /// have their registrations rolled back, hanging on the `await
    /// pressedEvents.next()` they expect. Production code never flips this.
    nonisolated(unsafe) static var skipTapInstall: Bool = false

    func configure(cancelWindow: TimeInterval, handsFreeEnabled: Bool, upgradeKeycode: Int?) {
        lock.lock()
        core.cancelWindow = cancelWindow
        core.handsFreeEnabled = handsFreeEnabled
        core.upgradeKeycode = upgradeKeycode
        lock.unlock()
    }

    func unwatch(_ accelerator: String? = nil) {
        lock.lock()
        let shouldTeardown = core.unwatch(accelerator)
        lock.unlock()
        if shouldTeardown { teardownTap() }
    }

    #if DEBUG
    // Test seam — bypass the CGEventTap so unit tests can exercise dispatch.
    @discardableResult
    func simulateKeyDown(keycode: Int, flags: CGEventFlags = []) -> Bool {
        dispatchKeyDown(keycode: keycode, flags: flags)
    }

    @discardableResult
    func simulateKeyUp(keycode: Int) -> Bool {
        dispatchKeyUp(keycode: keycode)
    }

    func simulateFlagsChanged(keycode: Int, flags: CGEventFlags) {
        dispatchFlagsChanged(keycode: keycode, flags: flags)
    }
    #endif

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        // `.defaultTap` (not `.listenOnly`) is required to swallow the hold
        // shortcut's main-key events. Without that, terminal/text apps see
        // the auto-repeating key (e.g. Space) and insert characters in front
        // of the pasted transcript. We return `nil` from the callback for
        // matched main-key events; non-matching events still pass through.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: HoldDetector.tapCallback,
            userInfo: opaqueSelf
        ) else {
            logger.error("CGEvent.tapCreate returned nil — Accessibility likely denied or revoked")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        let timer = Timer(timeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.sweepTimer = timer
        logger.info("CGEventTap installed on kCGSessionEventTap (keyDown + keyUp + flagsChanged)")
        return true
    }

    private func teardownTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        sweepTimer?.invalidate()
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        self.tap = nil
        self.runLoopSource = nil
        self.sweepTimer = nil
        logger.info("CGEventTap torn down")
    }

    // Lock-protected entry points the C callback uses. The callback runs on
    // the main runloop thread; the lock is here only to keep the compiler /
    // future contributors honest, since the C bridge is non-isolated.
    fileprivate func dispatchKeyDown(keycode: Int, flags: CGEventFlags) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return core.dispatchKeyDown(keycode: keycode, flags: flags)
    }

    fileprivate func dispatchKeyUp(keycode: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let consumed = core.dispatchKeyUp(keycode: keycode)
        schedulePendingExpiry()
        return consumed
    }

    fileprivate func dispatchFlagsChanged(keycode: Int, flags: CGEventFlags) {
        lock.lock()
        defer { lock.unlock() }
        core.dispatchFlagsChanged(keycode: keycode, flags: flags)
        schedulePendingExpiry()
    }

    // A short hands-free tap opened its second-tap window; lapse it even if
    // no further key event arrives. Caller holds the lock.
    private func schedulePendingExpiry() {
        guard let deadline = core.pendingDeadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.expirePending()
        }
    }

    /// Ends the active shortcut as if released (recording cap). Thread-safe.
    func forceRelease() {
        lock.lock()
        defer { lock.unlock() }
        core.forceRelease()
    }

    private func expirePending() {
        lock.lock()
        defer { lock.unlock() }
        core.expirePending()
    }

    fileprivate func reenableTapIfNeeded() {
        lock.lock()
        let storm = stormGuard.shouldRecreate(at: ProcessInfo.processInfo.systemUptime)
        lock.unlock()
        if storm {
            // Never invalidate the port from inside its own callback.
            logger.warning("CGEventTap disable storm — recreating tap")
            DispatchQueue.main.async { [weak self] in self?.recreateTap() }
            return
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        // Events (notably keyUps) were dropped while the tap was disabled.
        reconcile()
    }

    // Destroys and rebuilds tap + run loop source + timer, keeping the
    // registrations. teardownTap() first so taps/sources never duplicate.
    private func recreateTap() {
        guard tap != nil else { return }
        teardownTap()
        if !installTap() {
            logger.error("CGEventTap recreate failed — waiting for Accessibility to be restored")
            startAccessibilityPolling()
        }
        reconcile()
    }

    private func startAccessibilityPolling() {
        guard accessibilityPollTimer == nil else { return }
        logger.info("CGEventTap pending — polling Accessibility every 1 s")
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.retryTapIfPending()
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPollTimer = timer
    }

    /// Installs the pending tap once Accessibility is granted. Driven by the
    /// 1 s poll and by app activation (AppDelegate). No-op otherwise.
    func retryTapIfPending() {
        // Polling only runs with registrations: unwatch-to-empty tears it down.
        guard accessibilityPollTimer != nil, tap == nil, AXIsProcessTrusted(), installTap() else { return }
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        logger.info("Accessibility granted — CGEventTap installed without relaunch")
        reconcile()
        onAccessibilityGranted?()
    }

    private func handleWake() {
        lock.lock()
        stormGuard.noteWake(at: ProcessInfo.processInfo.systemUptime)
        lock.unlock()
        guard tap != nil else { return }
        logger.info("wake — recreating CGEventTap")
        recreateTap()
    }

    private func tick() {
        reconcile()
        if let tap, !CFMachPortIsValid(tap) || !CGEvent.tapIsEnabled(tap: tap) {
            logger.warning("watchdog: CGEventTap dead or disabled — recreating")
            recreateTap()
        }
        let secureOn = IsSecureEventInputEnabled()
        if secureOn && !secureInputWasOn {
            onSecureInputEnabled?(Self.secureInputOwnerName())
        }
        secureInputWasOn = secureOn
    }

    // Best-effort: `kCGSSessionSecureInputPID` is an undocumented session
    // dictionary key. Absent → nil, the warning just omits the app name.
    private static func secureInputOwnerName() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? pid_t else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    func reconcile() {
        lock.lock()
        defer { lock.unlock() }
        core.reconcile(isDown: Self.isKeyDown)
    }

    // Live key state. Modifiers go through the flags so the right-hand
    // Cmd/Opt/Ctrl/Shift (distinct keycodes) count as held too.
    // `.hidSystemState`, not `.combinedSessionState`: the tap swallows the
    // shortcut's main key, so the session state never sees it down and the
    // 5 s sweep would "release" a key the user is still holding (G-029).
    private static func isKeyDown(_ keycode: Int) -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        switch keycode {
        case Keycode.meta: return flags.contains(.maskCommand)
        case Keycode.control: return flags.contains(.maskControl)
        case Keycode.alt: return flags.contains(.maskAlternate)
        case Keycode.shift: return flags.contains(.maskShift)
        case Keycode.fn: return flags.contains(.maskSecondaryFn)
        default: return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keycode))
        }
    }

    // Static C-compatible callback. Bridges the opaque pointer back to the
    // instance, then forwards the event into HoldDetectorCore. Returns `nil`
    // for events the core consumed (matched main-key of a registered hold
    // shortcut); other events pass through unchanged for zero latency added.
    //
    // NO MainActor.assumeIsolated here: see class-level note.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let detector = Unmanaged<HoldDetector>.fromOpaque(userInfo).takeUnretainedValue()

        let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        switch type {
        case .keyDown:
            if detector.dispatchKeyDown(keycode: keycode, flags: flags) {
                return nil
            }
        case .keyUp:
            if detector.dispatchKeyUp(keycode: keycode) {
                return nil
            }
        case .flagsChanged:
            // flagsChanged signals modifier press/release: drives modifier-only
            // shortcuts (Fn, Control+Alt) and releases of chorded ones. Never
            // swallow — the OS needs modifier state changes to reach the
            // focused app.
            detector.dispatchFlagsChanged(keycode: keycode, flags: flags)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            detector.reenableTapIfNeeded()
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
