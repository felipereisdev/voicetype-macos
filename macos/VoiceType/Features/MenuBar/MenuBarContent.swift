import AppKit
import SwiftUI

/// Content of the `MenuBarExtra` dropdown. `openWindow(id: "settings")` routes
/// through SwiftUI to the Window scene declared in `VoiceTypeApp`, which owns
/// the policy flip that keeps a `.accessory` app on screen.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppDependencies.self) private var deps

    var body: some View {
        Button {
            openWindow(id: "settings")
            // The Window scene's onAppear flips the policy, but on first open
            // we also need to bring the app foreground so the new window
            // becomes key + the user sees it.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            Label("Configurações…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            openWindow(id: HistoryWindow.identifier)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            Label("Histórico…", systemImage: "clock.arrow.circlepath")
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Divider()

        Button {
            deps.meetingRecorder.toggle()
        } label: {
            if deps.meetingRecorder.isRecording {
                Label("Parar gravação", systemImage: "stop.circle")
            } else {
                Label("Gravar reunião", systemImage: "record.circle")
            }
        }

        Button {
            deps.meetingRecorder.reprocessLatest()
        } label: {
            Label("Reprocessar última reunião", systemImage: "arrow.clockwise")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Sair do VoiceType", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
