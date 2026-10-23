import AVFoundation
import Foundation
import Observation

/// Plays one exported file at a time, with pause and seek.
@MainActor @Observable
final class PlaybackController {
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Starts `url`, or toggles pause when it is already loaded.
    func toggle(_ url: URL) {
        if currentURL == url, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                resume(player)
            }
            return
        }
        load(url)
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(seconds, 0), player.duration)
        player.currentTime = clamped
        position = clamped
    }

    func stop() {
        ticker?.cancel()
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
        position = 0
        duration = 0
    }

    // MARK: - Private

    private func load(_ url: URL) {
        stop()
        errorMessage = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            player = newPlayer
            currentURL = url
            duration = newPlayer.duration
            resume(newPlayer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resume(_ player: AVAudioPlayer) {
        guard player.play() else {
            errorMessage = "Playback could not start."
            return
        }
        isPlaying = true
        startTicker()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
                if self.isPlaying, !player.isPlaying {
                    // Reached the end.
                    self.isPlaying = false
                    self.position = 0
                    player.currentTime = 0
                    return
                }
                if !self.isPlaying { return }
            }
        }
    }
}
