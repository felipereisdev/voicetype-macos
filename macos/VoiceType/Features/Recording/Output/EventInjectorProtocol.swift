import AppKit
import Carbon.HIToolbox
import CoreGraphics
import os

public protocol EventInjectorProtocol: Sendable {
    // Synthesizes Cmd+V at the HID event tap. Throws if CGEvent creation fails.
    func sendCommandV() throws

    // Synthesizes a Return keypress at the HID event tap with no modifiers.
    // Throws if CGEvent creation fails.
    func sendReturn() throws
}

public enum EventInjectorError: Error, Equatable {
    case eventCreationFailed
    case accessibilityNotGranted
}

// Virtual key code that types "v" (with ⌘ held) in the current keyboard
// layout — Dvorak moves it off ANSI 0x09. TIS APIs must run on the main
// thread (G-028), so the main actor resolves into a lock-protected cache and
// the off-main injector only reads it. Refreshed on every layout switch.
enum PasteKeyCode {
    static let ansiV: CGKeyCode = 0x09
    private static let cached = OSAllocatedUnfairLock(initialState: ansiV)

    static var v: CGKeyCode { cached.withLock { $0 } }

    @MainActor static func startObserving() {
        refresh()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { refresh() }
        }
    }

    @MainActor static func refresh() {
        let code = resolve(for: "v", translate: currentLayoutTranslator())
        cached.withLock { $0 = code }
    }

    // UCKeyTranslate maps keycode → character; the inverse needs a scan.
    // Lowest matching keycode wins; no match/no layout → ANSI fallback.
    static func resolve(for character: String, translate: ((CGKeyCode) -> String?)?) -> CGKeyCode {
        guard let translate else { return ansiV }
        return (0..<128).lazy.map { CGKeyCode($0) }.first { translate($0) == character } ?? ansiV
    }

    @MainActor private static func currentLayoutTranslator() -> ((CGKeyCode) -> String?)? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        let commandModifier = UInt32((cmdKey >> 8) & 0xFF)
        return { keyCode in
            layoutData.withUnsafeBytes { buffer -> String? in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDown), commandModifier, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
                )
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: chars, count: length).lowercased()
            }
        }
    }
}

public struct SystemEventInjector: EventInjectorProtocol {
    // macOS virtual key code for Return.
    private static let kVK_Return: CGKeyCode = 0x24

    public init() {}

    // tapLocation == .cghidEventTap delivers as if from a real keyboard.
    // Source == nil lets the system attribute the event to the current process,
    // which is what we want for Accessibility authorization purposes.
    public func sendCommandV() throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: PasteKeyCode.v, keyDown: true) else {
            throw EventInjectorError.eventCreationFailed
        }
        down.flags = .maskCommand
        down.post(tap: .cghidEventTap)

        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: PasteKeyCode.v, keyDown: false) else {
            throw EventInjectorError.eventCreationFailed
        }
        up.flags = .maskCommand
        up.post(tap: .cghidEventTap)
    }

    public func sendReturn() throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: Self.kVK_Return, keyDown: true) else {
            throw EventInjectorError.eventCreationFailed
        }
        down.post(tap: .cghidEventTap)

        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: Self.kVK_Return, keyDown: false) else {
            throw EventInjectorError.eventCreationFailed
        }
        up.post(tap: .cghidEventTap)
    }
}
