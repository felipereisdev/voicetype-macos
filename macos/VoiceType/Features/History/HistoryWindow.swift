import SwiftUI
import Core

/// SwiftUI `Window` scene that hosts the history list. Same policy-flip pattern
/// as the Settings scene (see VoiceTypeApp): `.accessory` apps need to flip to
/// `.regular` while a window is open so it becomes key and shows a Dock icon,
/// then flip back when it closes.
struct HistoryWindow: Scene {
    static let identifier = "history"

    let viewModel: HistoryViewModel

    var body: some Scene {
        Window(HistoryStrings.title, id: Self.identifier) {
            HistoryView(viewModel: viewModel)
                .onAppear { ActivationPolicyTracker.enter() }
                .onDisappear { ActivationPolicyTracker.leave() }
        }
        .windowResizability(.contentMinSize)
        .commandsRemoved()
    }
}
