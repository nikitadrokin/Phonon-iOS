import Foundation
import Observation
import PhononTTS

/// Plays a short sample sentence in the selected voice through `PhononPlayer`.
@MainActor @Observable
final class VoicePreviewer {
    private(set) var isPlaying = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var player: PhononPlayer?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let sampleText = "This is how your document will sound. Numbers like 1,250, dates like March 3rd, and web addresses like example.com are read aloud."

    func toggle(using phonon: Phonon) {
        if isPlaying {
            stop()
            return
        }
        errorMessage = nil
        isPlaying = true
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
            if !Task.isCancelled { self?.isPlaying = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        isPlaying = false
    }

    private func makePlayer() throws -> PhononPlayer {
        if let player { return player }
        let created = try PhononPlayer()
        player = created
        return created
    }
}
