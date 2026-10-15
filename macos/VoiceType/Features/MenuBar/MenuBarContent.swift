import AppKit
import SwiftUI

/// Content of the `MenuBarExtra` dropdown. `openWindow(id: MainWindowRouter.windowID)` routes
/// through SwiftUI to the Window scene declared in `VoiceTypeApp`, which owns
/// the policy flip that keeps a `.accessory` app on screen.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppDependencies.self) private var deps
    @Environment(MainWindowRouter.self) private var router

    var body: some View {
        Button {
            open(.settings(.general))
        } label: {
            Label("Configurações…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            open(.history)
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

    // Same window for both entries: select first, so an already-open window
    // switches pane and a new one opens on it. The Window scene's onAppear
    // flips the policy, but we also bring the app foreground so the window
    // becomes key + the user sees it.
    private func open(_ destination: MainDestination) {
        router.selection = destination
        openWindow(id: MainWindowRouter.windowID)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
