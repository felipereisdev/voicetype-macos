import Foundation
import Testing
@testable import Core

@Suite("OKVault")
struct OKVaultTests {

    @Test func detectsProjectRootByDotOkDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        #expect(!OKVault.isProjectRoot(root))

        let marker = root.appendingPathComponent(".ok")
        try Data().write(to: marker)
        #expect(!OKVault.isProjectRoot(root))

        try fm.removeItem(at: marker)
        try fm.createDirectory(at: marker, withIntermediateDirectories: false)
        #expect(OKVault.isProjectRoot(root))
    }

    @Test func urlExpandsTildeAsDirectory() {
        let url = OKVault.url("~/MegaBrain")
        #expect(url.path == (NSHomeDirectory() as NSString).appendingPathComponent("MegaBrain"))
        #expect(url.hasDirectoryPath)
        #expect(OKVault.url("/tmp/MB").path == "/tmp/MB")
    }
}
