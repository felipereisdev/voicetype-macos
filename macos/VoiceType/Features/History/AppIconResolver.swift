import AppKit

enum AppIconResolver {
    private static var cache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    static func icon(forBundleID bundleID: String) -> NSImage {
        if bundleID.isEmpty {
            return genericIcon()
        }
        cacheLock.lock()
        if let cached = cache[bundleID] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let workspace = NSWorkspace.shared
        let icon: NSImage
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            icon = workspace.icon(forFile: url.path)
        } else {
            icon = genericIcon()
        }
        icon.size = NSSize(width: 16, height: 16)

        cacheLock.lock()
        cache[bundleID] = icon
        cacheLock.unlock()
        return icon
    }

    static func displayName(forBundleID bundleID: String) -> String {
        if bundleID.isEmpty { return "Desconhecido" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                      ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) {
            return name
        }
        return bundleID
    }

    private static func genericIcon() -> NSImage {
        if let image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Aplicativo desconhecido") {
            image.size = NSSize(width: 16, height: 16)
            return image
        }
        return NSImage(size: NSSize(width: 16, height: 16))
    }

    static func resetCacheForTests() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}
