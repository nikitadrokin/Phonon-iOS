import AVFoundation
import Foundation
import Observation
import PhononTTS

/// Plays a short sample sentence in the selected voice through `PhononPlayer`.
@MainActor @Observable
final class VoicePreviewer {
    private(set) var isPlaying = false
    private(set) var errorMessage: String?
    /// The voice the current preview is speaking in.
    private(set) var playingVoice: String?

    @ObservationIgnored private var player: PhononPlayer?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Called just before a preview starts, so file playback can pause.
    @ObservationIgnored var onWillPlay: (@MainActor () -> Void)?

    static let sampleText = "This is how your document will sound. Numbers like 1,250, dates like March 3rd, and web addresses like example.com are read aloud."

    func toggle(using phonon: Phonon) {
        if isPlaying {
            stop()
            return
        }
        play(using: phonon)
    }

    /// Previews `voice` (switching the store to it first), or stops when it is already playing.
    func toggle(voice: String, store: ModelStore) {
        if isPlaying, playingVoice == voice {
            stop()
            return
        }
        stop()
        guard let phonon = store.phonon else { return }
        onWillPlay?()
        playingVoice = voice
        isPlaying = true
        task = Task { [weak self] in
            await store.selectVoice(voice)
            guard !Task.isCancelled else { return }
            self?.play(using: phonon)
        }
    }

    private func play(using phonon: Phonon) {
        onWillPlay?()
        task?.cancel()
        errorMessage = nil
        isPlaying = true
        playingVoice = phonon.voice
        task = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            var sampleCount = 0
            do {
                guard let player = try self?.makePlayer() else { return }
                for try await chunk in phonon.stream(Self.sampleText) {
                    player.enqueue(chunk)
                    sampleCount += chunk.count
                }
                // Keep the button in its playing state until the queued audio has played out.
                let total = Duration.seconds(Double(sampleCount) / Phonon.sampleRate)
                let remaining = total - start.duration(to: clock.now)
                if remaining > .zero { try await Task.sleep(for: remaining) }
            } catch {
                if !Task.isCancelled { self?.errorMessage = error.localizedDescription }
            }
            if !Task.isCancelled {
                self?.isPlaying = false
                self?.playingVoice = nil
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        isPlaying = false
        playingVoice = nil
    }

    private func makePlayer() throws -> PhononPlayer {
        if let player { return player }
        // Configure the session here so previews use the same spoken-audio mode as file playback.
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let created = try PhononPlayer(configureSession: false)
        player = created
        return created
    }
}
