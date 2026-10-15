import Carbon.HIToolbox
import CoreGraphics
import Foundation

// Subset of macOS virtual keycodes mapped from accelerator tokens.
// Mirrors the UiohookKey table in src/main/hold-detector.ts but uses Carbon's
// kVK_* values so events from CGEvent.keyCode match directly without translation.
enum Keycode {
    static let meta = Int(kVK_Command)
    static let control = Int(kVK_Control)
    static let alt = Int(kVK_Option)
    static let shift = Int(kVK_Shift)
    static let space = Int(kVK_Space)
    static let tab = Int(kVK_Tab)
    static let backspace = Int(kVK_Delete)
    static let delete = Int(kVK_ForwardDelete)
    static let enter = Int(kVK_Return)
    static let escape = Int(kVK_Escape)
    static let fn = Int(kVK_Function)
    // Globe key on newer Apple keyboards; normalized to `fn` on flagsChanged.
    static let globe = 179
    // Right-hand modifiers have their own keycodes; flagsChanged normalizes
    // them to the left-hand ones the registrations store.
    static let rightCommand = Int(kVK_RightCommand)
    static let rightShift = Int(kVK_RightShift)
    static let rightOption = Int(kVK_RightOption)
    static let rightControl = Int(kVK_RightControl)

    static let a = Int(kVK_ANSI_A), b = Int(kVK_ANSI_B), c = Int(kVK_ANSI_C)
    static let d = Int(kVK_ANSI_D), e = Int(kVK_ANSI_E), f = Int(kVK_ANSI_F)
    static let g = Int(kVK_ANSI_G), h = Int(kVK_ANSI_H), i = Int(kVK_ANSI_I)
    static let j = Int(kVK_ANSI_J), k = Int(kVK_ANSI_K), l = Int(kVK_ANSI_L)
    static let m = Int(kVK_ANSI_M), n = Int(kVK_ANSI_N), o = Int(kVK_ANSI_O)
    static let p = Int(kVK_ANSI_P), q = Int(kVK_ANSI_Q), r = Int(kVK_ANSI_R)
    static let s = Int(kVK_ANSI_S), t = Int(kVK_ANSI_T), u = Int(kVK_ANSI_U)
    static let v = Int(kVK_ANSI_V), w = Int(kVK_ANSI_W), x = Int(kVK_ANSI_X)
    static let y = Int(kVK_ANSI_Y), z = Int(kVK_ANSI_Z)

    static let f1 = Int(kVK_F1), f2 = Int(kVK_F2), f3 = Int(kVK_F3)
    static let f4 = Int(kVK_F4), f5 = Int(kVK_F5), f6 = Int(kVK_F6)
    static let f7 = Int(kVK_F7), f8 = Int(kVK_F8), f9 = Int(kVK_F9)
    static let f10 = Int(kVK_F10), f11 = Int(kVK_F11), f12 = Int(kVK_F12)

    static let zero = Int(kVK_ANSI_0), one = Int(kVK_ANSI_1), two = Int(kVK_ANSI_2)
    static let three = Int(kVK_ANSI_3), four = Int(kVK_ANSI_4), five = Int(kVK_ANSI_5)
    static let six = Int(kVK_ANSI_6), seven = Int(kVK_ANSI_7), eight = Int(kVK_ANSI_8)
    static let nine = Int(kVK_ANSI_9)

    static let modifiers: Set<Int> = [meta, control, alt, shift, fn]

    static func normalizedModifier(_ keycode: Int) -> Int {
        switch keycode {
        case rightCommand: return meta
        case rightShift: return shift
        case rightOption: return alt
        case rightControl: return control
        case globe: return fn
        default: return keycode
        }
    }

    static func flag(forModifier keycode: Int) -> CGEventFlags? {
        switch keycode {
        case meta: return .maskCommand
        case control: return .maskControl
        case alt: return .maskAlternate
        case shift: return .maskShift
        case fn: return .maskSecondaryFn
        default: return nil
        }
    }

    static let modifierFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
}

private let tokenToKeycode: [String: Int] = {
    var m: [String: Int] = [
        "Command": Keycode.meta,
        "Cmd": Keycode.meta,
        "CommandOrControl": Keycode.meta,
        "CmdOrCtrl": Keycode.meta,
        "Control": Keycode.control,
        "Ctrl": Keycode.control,
        "Alt": Keycode.alt,
        "Option": Keycode.alt,
        "Shift": Keycode.shift,
        "Space": Keycode.space,
        "Tab": Keycode.tab,
        "Backspace": Keycode.backspace,
        "Delete": Keycode.delete,
        "Enter": Keycode.enter,
        "Return": Keycode.enter,
        "Escape": Keycode.escape,
        "Esc": Keycode.escape,
        "Fn": Keycode.fn,
        "Globe": Keycode.fn,
    ]
    let letters: [(String, Int)] = [
        ("A", Keycode.a), ("B", Keycode.b), ("C", Keycode.c), ("D", Keycode.d),
        ("E", Keycode.e), ("F", Keycode.f), ("G", Keycode.g), ("H", Keycode.h),
        ("I", Keycode.i), ("J", Keycode.j), ("K", Keycode.k), ("L", Keycode.l),
        ("M", Keycode.m), ("N", Keycode.n), ("O", Keycode.o), ("P", Keycode.p),
        ("Q", Keycode.q), ("R", Keycode.r), ("S", Keycode.s), ("T", Keycode.t),
        ("U", Keycode.u), ("V", Keycode.v), ("W", Keycode.w), ("X", Keycode.x),
        ("Y", Keycode.y), ("Z", Keycode.z),
    ]
    for (k, v) in letters { m[k] = v }
    let digits: [(String, Int)] = [
        ("0", Keycode.zero), ("1", Keycode.one), ("2", Keycode.two), ("3", Keycode.three),
        ("4", Keycode.four), ("5", Keycode.five), ("6", Keycode.six), ("7", Keycode.seven),
        ("8", Keycode.eight), ("9", Keycode.nine),
    ]
    for (k, v) in digits { m[k] = v }
    let fns: [(String, Int)] = [
        ("F1", Keycode.f1), ("F2", Keycode.f2), ("F3", Keycode.f3), ("F4", Keycode.f4),
        ("F5", Keycode.f5), ("F6", Keycode.f6), ("F7", Keycode.f7), ("F8", Keycode.f8),
        ("F9", Keycode.f9), ("F10", Keycode.f10), ("F11", Keycode.f11), ("F12", Keycode.f12),
    ]
    for (k, v) in fns { m[k] = v }
    return m
}()

// Pure decision engine. No CoreGraphics state; safe to unit-test without an
// event tap or accessibility permission.
//
// Deviation from Phase 4 plan:
// - Plan used Sindre Sorhus's KeyboardShortcuts library for press detection and
//   reserved this core for release-only. Skipped: single CGEventTap shim now
//   handles both press (keyDown matching main key + modifier flags) and release
//   (keyUp / flagsChanged for any registered keycode). Phase 6 may revisit if
//   Settings UI needs the library's NSView shortcut recorder.
struct HoldDetectorCore {

    struct ParseResult {
        let keycodes: Set<Int>?
        let error: String?
        var ok: Bool { keycodes != nil }
    }

    struct WatchResult: Equatable {
        let ok: Bool
        let error: String?
        static let success = WatchResult(ok: true, error: nil)
        static func failure(_ msg: String) -> WatchResult { .init(ok: false, error: msg) }
    }

    enum Phase: Equatable {
        case holding
        // Short tap released; recording keeps going for one double-tap window.
        case awaitingSecondTap(releasedAt: TimeInterval)
        // Hands-free: records until the next tap (stop + paste) or Esc (cancel).
        case locked
    }

    struct Registration {
        let keycodes: Set<Int>
        let onPress: @Sendable () -> Void
        let onRelease: @Sendable () -> Void
        let onCancel: @Sendable () -> Void
        let onLock: @Sendable () -> Void
        // True between a successful onPress and its corresponding onRelease.
        // Without this flag, dispatchKeyUp would fire onRelease + swallow the
        // keyUp event for any tap of the shortcut's main key — even when the
        // user just typed that letter alone (no modifiers). Swallowed keyUps
        // left the focused app seeing a keyDown without a keyUp, which after
        // ~400ms triggers macOS's Press-and-Hold accent picker (ñ/ń/ņ/ň, etc.).
        var isActive: Bool = false
        // Clock reading at the leading-edge press; drives the cancel window.
        var pressedAt: TimeInterval = 0
        // Set when an extra key cancelled the hold. Auto-repeats of the still
        // held main key must not re-fire onPress until a keyUp ends the chord.
        var isSuppressed: Bool = false
        // Gesture phase while active. PTT stays in `.holding`; hands-free
        // moves through the others with the keys already up.
        var phase: Phase = .holding

        var modifierMask: CGEventFlags { Self.maskFor(keycodes: keycodes) }
        /// nil for modifier-only shortcuts (Fn, Control+Alt) — those are
        /// driven by flagsChanged instead of keyDown.
        var mainKey: Int? { keycodes.subtracting(Keycode.modifiers).first }

        private static func maskFor(keycodes: Set<Int>) -> CGEventFlags {
            CGEventFlags(keycodes.compactMap(Keycode.flag(forModifier:)))
        }
    }

    private(set) var registrations: [String: Registration] = [:]
    /// Keycodes whose keyDown was swallowed and whose paired keyUp must also
    /// be swallowed so the focused app doesn't see a stray keyUp without a
    /// matching keyDown. Populated on consumed keyDowns; drained on keyUp.
    private var pendingSwallowUps: Set<Int> = []
    private let clock: () -> TimeInterval
    /// An extra keyDown within this many seconds of the press means the user
    /// is reaching for another shortcut (Opt+letter, Fn+arrow): cancel the
    /// recording. After it, extra keys are ignored and recording continues.
    var cancelWindow: TimeInterval = 1.0
    /// Off = pure push-to-talk. On: a tap shorter than `doubleTapWindow`
    /// followed by a second tap within it locks hands-free; an isolated short
    /// tap is discarded once the window lapses.
    var handsFreeEnabled = false
    var doubleTapWindow: TimeInterval = 0.5
    /// Pressing this key while holding the shortcut upgrades PTT to
    /// hands-free without restarting the recording. Ignored when it is part
    /// of the shortcut itself.
    var upgradeKeycode: Int?

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    // Mirrors watch(accelerator, onRelease) in hold-detector.ts. Returns a
    // WatchResult and on success mutates registrations. Caller (CGEventTap shim)
    // is responsible for starting the tap if it wasn't running.
    mutating func watch(
        _ accelerator: String,
        onPress: @escaping @Sendable () -> Void,
        onRelease: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void = {},
        onLock: @escaping @Sendable () -> Void = {}
    ) -> WatchResult {
        let parsed = Self.parseAccelerator(accelerator)
        guard let codes = parsed.keycodes else {
            return .failure(parsed.error ?? "parse-failed")
        }
        registrations[accelerator] = Registration(
            keycodes: codes,
            onPress: onPress,
            onRelease: onRelease,
            onCancel: onCancel,
            onLock: onLock
        )
        return .success
    }

    // Mirrors unwatch(accelerator?). nil clears all. Returns true when the
    // caller should teardown the underlying event tap (registrations empty).
    @discardableResult
    mutating func unwatch(_ accelerator: String? = nil) -> Bool {
        // A gesture in flight would lose its release with the registration
        // (config save mid-take) — mic and state machine stuck recording.
        for (key, reg) in registrations where reg.isActive && (accelerator == nil || key == accelerator) {
            reg.onRelease()
        }
        if let acc = accelerator {
            registrations.removeValue(forKey: acc)
        } else {
            registrations.removeAll()
        }
        return registrations.isEmpty
    }

    // Fires onPress for every registration whose mainKey matches `keycode` and
    // whose required modifier mask is fully present in `flags`. Returns `true`
    // when at least one registration matched — the caller (CGEventTap shim) uses
    // this to swallow the event so the focused app doesn't receive the
    // hold-shortcut's main key (terminal would otherwise auto-repeat spaces).
    //
    // onPress only fires on the leading-edge match (transition from inactive to
    // active). Auto-repeats while the shortcut is still held re-consume the
    // event but don't fire onPress again.
    //
    // A keyDown outside a held shortcut within `cancelWindow` fires
    // onCancel instead (never swallowed — the extra key belongs to the app).
    //
    // Hands-free: the upgrade key while holding locks (swallowed); a matching
    // press while awaiting the second tap locks; a press while locked fires
    // onRelease; Esc while hands-free fires onCancel (swallowed).
    @discardableResult
    mutating func dispatchKeyDown(keycode: Int, flags: CGEventFlags) -> Bool {
        let now = clock()
        expirePending()

        var consumed = false
        for key in registrations.keys {
            guard var reg = registrations[key], reg.isActive else { continue }
            if reg.phase != .holding {
                guard keycode == Keycode.escape else { continue }
                reg.onCancel()
                reg.isActive = false
                consumed = true
            } else if reg.keycodes.contains(keycode) {
                continue
            } else if handsFreeEnabled && keycode == upgradeKeycode {
                reg.phase = .locked
                reg.onLock()
                consumed = true
            } else if now - reg.pressedAt < cancelWindow {
                reg.onCancel()
                reg.isActive = false
                reg.isSuppressed = true
            }
            registrations[key] = reg
        }
        if consumed {
            pendingSwallowUps.insert(keycode)
            return true
        }

        for key in registrations.keys {
            guard var reg = registrations[key] else { continue }
            guard let main = reg.mainKey, main == keycode else { continue }
            let needed = reg.modifierMask
            guard flags.intersection(needed) == needed else { continue }
            Self.press(&reg, now: now)
            registrations[key] = reg
            pendingSwallowUps.insert(keycode)
            consumed = true
        }
        return consumed
    }

    // Matched press of a shortcut (main key or full modifier set), by phase.
    private static func press(_ reg: inout Registration, now: TimeInterval) {
        if reg.isActive {
            switch reg.phase {
            case .holding:
                break  // auto-repeat
            case .awaitingSecondTap:
                reg.phase = .locked
                reg.onLock()
            case .locked:
                reg.onRelease()
                reg.isActive = false
                reg.isSuppressed = true  // this tap's own keyUp/repeats are spent
            }
        } else if !reg.isSuppressed {
            reg.onPress()
            reg.isActive = true
            reg.pressedAt = now
            reg.phase = .holding
        }
    }

    // Modifier press/release. The caller never swallows flagsChanged — the OS
    // needs it to keep modifier state in sync with the focused app.
    // - Release → same path as a keyUp (ends PTT, opens the double-tap window).
    // - Press completing a modifier-only shortcut's exact set → press.
    // - Press of an extra modifier while holding, inside the cancel window →
    //   onCancel (Ctrl+Opt+Cmd… means another shortcut).
    mutating func dispatchFlagsChanged(keycode rawKeycode: Int, flags: CGEventFlags) {
        let keycode = Keycode.normalizedModifier(rawKeycode)
        let held = flags.intersection(Keycode.modifierFlags)
        guard let flag = Keycode.flag(forModifier: keycode), held.contains(flag) else {
            dispatchKeyUp(keycode: keycode)
            return
        }
        let now = clock()
        expirePending()
        for key in registrations.keys {
            guard var reg = registrations[key] else { continue }
            if reg.isActive, reg.phase == .holding, !reg.keycodes.contains(keycode) {
                guard now - reg.pressedAt < cancelWindow else { continue }
                reg.onCancel()
                reg.isActive = false
                reg.isSuppressed = true
            } else if reg.mainKey == nil, held == reg.modifierMask {
                Self.press(&reg, now: now)
            } else {
                continue
            }
            registrations[key] = reg
        }
    }

    // Fires onRelease for every registration that is currently active and
    // lists `keycode` (modifier or main key) — releasing any part of an active
    // shortcut ends recording (push-to-talk semantics).
    //
    // Returns `true` only when the keyUp pairs with a keyDown we previously
    // swallowed — i.e., the keycode is in `pendingSwallowUps`. This keeps the
    // focused app's input state symmetric (keyDown/keyUp pairs) and prevents
    // unrelated keyUps from being eaten. Without this guard a configured
    // letter shortcut (e.g., Cmd+Shift+Z) would cause every solo `z` keystroke
    // to lose its keyUp, which macOS interprets as press-and-hold and triggers
    // the accent picker (ñ/ń/ņ/ň etc).
    //
    // Hands-free: a hold shorter than `doubleTapWindow` doesn't stop — it
    // opens the second-tap window; keyUps while awaiting/locked are ignored.
    @discardableResult
    mutating func dispatchKeyUp(keycode: Int) -> Bool {
        let now = clock()
        for key in registrations.keys {
            guard var reg = registrations[key] else { continue }
            guard reg.keycodes.contains(keycode) else { continue }
            if reg.isActive && reg.phase == .holding {
                if handsFreeEnabled && now - reg.pressedAt < doubleTapWindow {
                    reg.phase = .awaitingSecondTap(releasedAt: now)
                } else {
                    reg.onRelease()
                    reg.isActive = false
                }
            }
            // Main-key chords re-arm only on the main key's keyUp: releasing
            // a modifier first and re-pressing it while the main key still
            // auto-repeats must not start a new take.
            if reg.mainKey == nil || keycode == reg.mainKey {
                reg.isSuppressed = false
            }
            registrations[key] = reg
        }
        if pendingSwallowUps.contains(keycode) {
            pendingSwallowUps.remove(keycode)
            return true
        }
        return false
    }

    // Reconciles the core with the real keyboard after events may have been
    // lost (tap disabled by timeout/user input, missed keyUp). `isDown` reads
    // the live key state — injected so this stays testable without AppKit.
    // - Active shortcut with a key no longer down → onRelease (normal stop +
    //   process; the user did let go, we just never saw it).
    // - Suppressed (cancelled) chord fully released → re-armed.
    // - Swallow-pending keyUps for keys no longer down → dropped (phantoms).
    // Queries `isDown` only for keys the core thinks are held, so an idle
    // periodic sweep is free.
    mutating func reconcile(isDown: (Int) -> Bool) {
        for key in registrations.keys {
            guard var reg = registrations[key] else { continue }
            if reg.isActive, reg.phase == .holding, !reg.keycodes.allSatisfy(isDown) {
                reg.onRelease()
                reg.isActive = false
            }
            if reg.isSuppressed, !reg.keycodes.contains(where: isDown) {
                reg.isSuppressed = false
            }
            registrations[key] = reg
        }
        pendingSwallowUps = pendingSwallowUps.filter(isDown)
    }

    // Recording cap hit (5 min): end every active gesture as if released, so
    // the take finishes through the normal release path (stop + process).
    // Keys still physically held stay suppressed until their keyUp, so
    // auto-repeat can't start a new take; hands-free phases (keys already
    // up) re-arm right away — the next tap starts a fresh recording.
    mutating func forceRelease() {
        for key in registrations.keys {
            guard var reg = registrations[key], reg.isActive else { continue }
            reg.onRelease()
            reg.isActive = false
            reg.isSuppressed = reg.phase == .holding
            registrations[key] = reg
        }
    }

    /// Clock time when an awaiting short tap lapses — the shim schedules
    /// `expirePending()` for it. nil when nothing is pending.
    var pendingDeadline: TimeInterval? {
        registrations.values.compactMap { reg -> TimeInterval? in
            guard reg.isActive, case .awaitingSecondTap(let releasedAt) = reg.phase else { return nil }
            return releasedAt + doubleTapWindow
        }.min()
    }

    // Isolated short tap whose second-tap window lapsed → onCancel: the
    // take is discarded, never pasted.
    mutating func expirePending() {
        let now = clock()
        for key in registrations.keys {
            guard var reg = registrations[key], reg.isActive,
                  case .awaitingSecondTap(let releasedAt) = reg.phase,
                  now - releasedAt >= doubleTapWindow else { continue }
            reg.onCancel()
            reg.isActive = false
            registrations[key] = reg
        }
    }

    static func parseAccelerator(_ accelerator: String) -> ParseResult {
        guard !accelerator.isEmpty else {
            return ParseResult(keycodes: nil, error: "Accelerator vazio")
        }
        let tokens = accelerator
            .split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return ParseResult(keycodes: nil, error: "Accelerator vazio")
        }
        var codes = Set<Int>()
        for token in tokens {
            guard let code = tokenToKeycode[token] else {
                return ParseResult(keycodes: nil, error: "Token desconhecido: \(token)")
            }
            codes.insert(code)
        }
        return ParseResult(keycodes: codes, error: nil)
    }
}

// Decides whether a disabled tap gets a plain re-enable or a full recreate.
// macOS keeps disabling a tap whose callback stalls; blindly re-enabling it
// then spins forever. `limit` re-enables inside `window` seconds = storm →
// destroy + recreate the tap. Right after wake the system churns taps on its
// own, so re-enables within `wakeGrace` of a wake are not counted.
struct TapStormGuard {
    var limit = 5
    var window: TimeInterval = 10
    var wakeGrace: TimeInterval = 60
    private var reenables: [TimeInterval] = []
    private var lastWake: TimeInterval = -.infinity

    mutating func noteWake(at now: TimeInterval) {
        lastWake = now
        reenables.removeAll()
    }

    /// Records a tap-disabled event; `true` → recreate instead of re-enable.
    mutating func shouldRecreate(at now: TimeInterval) -> Bool {
        if now - lastWake < wakeGrace { return false }
        reenables = reenables.filter { now - $0 < window } + [now]
        guard reenables.count >= limit else { return false }
        reenables.removeAll()
        return true
    }
}
