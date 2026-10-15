import Core
import Foundation
import IOKit

enum ShortcutEvent: Sendable, Equatable {
    case pressed(Mode)
    case released(Mode)
    /// Hold aborted because another key joined the chord inside the cancel
    /// window — discard the audio, no paste.
    case cancelled(Mode)
    /// Hands-free locked (double tap or upgrade key): recording continues
    /// with the keys up until the next tap or Esc.
    case locked(Mode)
}

// Deviation from Phase 4 plan: no KeyboardShortcuts dependency. Press +
// release both come from the single CGEventTap inside HoldDetector. One
// AsyncStream stays as the public surface so the consumer doesn't know which
// mechanism generated which event — and so press/release/cancel keep their
// order (separate streams let a fast cancel overtake the still-starting press).
@MainActor
final class ShortcutManager {

    let events: AsyncStream<ShortcutEvent>

    private let continuation: AsyncStream<ShortcutEvent>.Continuation
    private let configStore: ConfigStore
    private let holdDetector: HoldDetector

    init(configStore: ConfigStore, holdDetector: HoldDetector) {
        self.configStore = configStore
        self.holdDetector = holdDetector
        var cont: AsyncStream<ShortcutEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // Reads the latest AppConfig and reconfigures both shortcuts. Idempotent —
    // safe on boot, on config change, and from tests.
    func applyConfig() async {
        let cfg: AppConfig
        do {
            cfg = try await configStore.load()
        } catch {
            return
        }

        holdDetector.unwatch()
        holdDetector.configure(
            cancelWindow: TimeInterval(cfg.shortcutCancelWindowMs) / 1000,
            handsFreeEnabled: cfg.handsFreeEnabled,
            upgradeKeycode: HoldDetectorCore.parseAccelerator(cfg.handsFreeUpgradeKey).keycodes?.first
        )

        // Registered first so a colliding dictation shortcut (same accelerator
        // key) overwrites it — dictation wins.
        if !cfg.voiceNoteShortcut.isEmpty {
            let events = continuation
            _ = holdDetector.watch(
                cfg.voiceNoteShortcut,
                onPress: { events.yield(.pressed(.voiceNote)) },
                onRelease: { events.yield(.released(.voiceNote)) },
                onCancel: { events.yield(.cancelled(.voiceNote)) },
                onLock: { events.yield(.locked(.voiceNote)) }
            )
        }

        let refineAccel = cfg.shortcuts.refine
        if !refineAccel.isEmpty {
            let events = continuation
            _ = holdDetector.watch(
                refineAccel,
                onPress: { events.yield(.pressed(.refine)) },
                onRelease: { events.yield(.released(.refine)) },
                onCancel: { events.yield(.cancelled(.refine)) },
                onLock: { events.yield(.locked(.refine)) }
            )
        }

        if cfg.translate.enabled && !cfg.shortcuts.translate.isEmpty {
            let events = continuation
            _ = holdDetector.watch(
                cfg.shortcuts.translate,
                onPress: { events.yield(.pressed(.translate)) },
                onRelease: { events.yield(.released(.translate)) },
                onCancel: { events.yield(.cancelled(.translate)) },
                onLock: { events.yield(.locked(.translate)) }
            )
        }
    }

    deinit {
        continuation.finish()
    }
}

enum KeyboardHardware {
    private static let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]  // USB, Bluetooth

    /// True when a keyboard that sends a real Fn/Globe keycode is attached:
    /// the built-in one or an Apple-vendor external. Reads IORegistry
    /// properties only — no IOHIDDeviceOpen, so no Input Monitoring prompt.
    static func hasAppleFnKey() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS
        else { return false }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { return false }
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard property("PrimaryUsagePage") as? Int == 1,
                  property("PrimaryUsage") as? Int == 6 else { continue }  // generic desktop / keyboard
            if property("Built-In") as? Bool == true { return true }
            if let vendor = property("VendorID") as? Int, appleVendorIDs.contains(vendor) { return true }
        }
    }
}
