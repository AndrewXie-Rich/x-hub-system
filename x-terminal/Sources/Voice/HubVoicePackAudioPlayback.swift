import Foundation
@preconcurrency import AVFoundation

@MainActor
enum HubVoicePackAudioPlayback {
    private static var activePlayer: AVAudioPlayer?

    static func playFile(atPath path: String) -> Bool {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return false }
        let url = URL(fileURLWithPath: normalizedPath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        if let activePlayer, activePlayer.isPlaying {
            activePlayer.stop()
        }
        activePlayer = nil

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            activePlayer = player
            return player.play()
        } catch {
            activePlayer = nil
            return false
        }
    }

    static func stop() -> Bool {
        guard let activePlayer else { return false }
        let wasPlaying = activePlayer.isPlaying
        activePlayer.stop()
        self.activePlayer = nil
        return wasPlaying
    }
}
