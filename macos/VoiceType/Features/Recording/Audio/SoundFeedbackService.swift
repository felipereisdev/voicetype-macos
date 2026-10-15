import AVFoundation
import Foundation
import os

/// Plays a short activation sound to confirm the user that recording is about
/// to start. The clip is bundled in the app and loaded once on first use; the
/// player is retained across plays to avoid the audio engine warmup cost on
/// each hotkey press.
@MainActor
final class SoundFeedbackService {
    private var player: AVAudioPlayer?
    private let logger = Logger(subsystem: "VoiceType", category: "SoundFeedback")

    func playActivation() {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "recording_start", withExtension: "wav") else {
                logger.warning("recording_start.wav not found in bundle")
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.prepareToPlay()
                player = p
            } catch {
                logger.error("failed to init AVAudioPlayer: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        player?.currentTime = 0
        player?.play()
    }
}
