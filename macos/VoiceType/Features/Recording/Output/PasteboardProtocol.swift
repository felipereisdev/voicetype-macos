import AppKit
import os

public struct PasteboardSnapshot: Sendable, Equatable {
    // Each item is a map from NSPasteboard.PasteboardType.rawValue to its raw Data.
    // Preserves all representations (string, RTF, image, custom) so multi-flavor
    // clipboards round-trip without loss.
    public let items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }
}

// Lazily-rendered string for the Cmd+V fallback: the text is only handed over
// when a consumer asks for it, which gives the Paster a "someone read it"
// signal. A read is NOT proof of insertion (apps read speculatively).
// The provider callback is nonisolated (runs on the main thread), so the flag
// is lock-protected instead of living on the Paster actor; `text` is
// immutable — hence the @unchecked Sendable.
public final class LazyPasteboardString: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    public let text: String
    private let read = OSAllocatedUnfairLock(initialState: false)

    public init(_ text: String) {
        self.text = text
    }

    public var wasRead: Bool {
        read.withLock { $0 }
    }

    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        read.withLock { $0 = true }
    }
}

public protocol PasteboardProtocol: Sendable {
    func snapshot() -> PasteboardSnapshot
    func writeString(_ text: String)
    // Promises `payload` as .string (marked concealed for clipboard managers).
    // Returns the changeCount right after our write, nil if it was rejected.
    func writeLazyString(_ payload: LazyPasteboardString) -> Int?
    func changeCount() -> Int
    func restore(_ snapshot: PasteboardSnapshot)
}

public struct SystemPasteboard: PasteboardProtocol {
    public init() {}

    public func snapshot() -> PasteboardSnapshot {
        let items = NSPasteboard.general.pasteboardItems ?? []
        let captured = items.map { item -> [String: Data] in
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type.rawValue] = data
                }
            }
            return entry
        }
        return PasteboardSnapshot(items: captured)
    }

    public func writeString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // nspasteboard.org convention (undocumented by Apple): clipboard managers
    // that honor it skip the item. Best-effort.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    public func writeLazyString(_ payload: LazyPasteboardString) -> Int? {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        guard item.setDataProvider(payload, forTypes: [.string]) else { return nil }
        item.setData(Data(), forType: Self.concealedType)
        guard pb.writeObjects([item]) else { return nil }
        return pb.changeCount
    }

    public func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    public func restore(_ snapshot: PasteboardSnapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let rebuilt: [NSPasteboardItem] = snapshot.items.map { entry in
            let item = NSPasteboardItem()
            for (rawType, data) in entry {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        pb.writeObjects(rebuilt)
    }
}
