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
    /// Playback speed, 0.5× to 2.5×. Remembered across launches.
    private(set) var rate: Float = {
        let saved = UserDefaults.standard.float(forKey: "playbackRate")
        return saved == 0 ? 1 : saved
    }()

    static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5]
    private static let rateKey = "playbackRate"

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var currentTitle: String? { currentURL?.deletingPathExtension().lastPathComponent }

    func setRate(_ newRate: Float) {
        rate = min(max(newRate, 0.5), 2.5)
        player?.rate = rate
        UserDefaults.standard.set(rate, forKey: Self.rateKey)
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

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
            newPlayer.enableRate = true
            newPlayer.prepareToPlay()
            newPlayer.rate = rate
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
