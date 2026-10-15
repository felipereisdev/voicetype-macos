import Foundation
import Core

@main
struct CoreDemo {
    static func main() async {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("voicetype-coredemo-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let configURL = tempDir.appendingPathComponent("config.json")
            let store = ConfigStore(fileURL: configURL)

            print("== VoiceTypeCore demo ==")
            print("store: \(configURL.path)")

            // 1) Load from an empty location -> defaults.
            let loaded1 = try await store.load()
            print("loaded(defaults): groq.apiKey='\(loaded1.groq.apiKey)', showHud=\(loaded1.showHud), translate.enabled=\(loaded1.translate.enabled)")
            precondition(loaded1 == AppConfig(), "first load must equal defaults")

            // 2) Mutate + save.
            var next = loaded1
            next.groq.apiKey = "gsk_demo_round_trip"
            next.showHud = false
            next.translate.enabled = true
            next.shortcuts.translate = "CommandOrControl+Shift+T"
            try await store.save(next)
            print("saved with groq.apiKey='\(next.groq.apiKey)'")

            // 3) Drop the cache and reload to prove the bytes hit disk.
            await store.resetForTests()
            let loaded2 = try await store.load()
            precondition(loaded2 == next, "second load must equal the saved value")
            print("reloaded: groq.apiKey='\(loaded2.groq.apiKey)', showHud=\(loaded2.showHud)")

            // 4) Exercise the state machine.
            let sm = AppStateMachine(recordingTimeout: .milliseconds(200))
            print("state machine starts at: \(await sm.state.rawValue)")

            // Subscribe synchronously BEFORE sending events so the continuation
            // is registered before any yield happens.
            let stream = sm.events.prefix(3)
            let task = Task {
                for await change in stream {
                    print("transition: \(change.from.rawValue) -> \(change.to.rawValue)")
                }
            }

            await sm.send(.start)
            await sm.send(.stop)
            await sm.send(.reset)
            await task.value
            let finalState = await sm.state
            precondition(finalState == .idle, "state machine must return to idle")

            print("== demo complete — round trip OK ==")
        } catch {
            FileHandle.standardError.write(Data("demo failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
