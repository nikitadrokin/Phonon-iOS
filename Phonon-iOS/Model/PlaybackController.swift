import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Plays one exported file at a time, with pause and seek.
///
/// Publishes the current file to the system Now Playing center and answers
/// remote commands, so playback continues in the background and can be
/// controlled from the Lock Screen, Control Center, headphones, and CarPlay.
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
    private static let skipInterval: Double = 15

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    /// Set when an interruption (a call, Siri) paused playback that should resume afterwards.
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private let playerDelegate = PlayerDelegate()

    var currentTitle: String? { currentURL?.deletingPathExtension().lastPathComponent }

    init() {
        playerDelegate.onFinish = { [weak self] in self?.didFinishPlaying() }
        configureRemoteCommands()
        observeAudioSession()
    }

    func setRate(_ newRate: Float) {
        rate = min(max(newRate, 0.5), 2.5)
        player?.rate = rate
        UserDefaults.standard.set(rate, forKey: Self.rateKey)
        updateNowPlayingPlayback()
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

    /// Starts `url`, or toggles pause when it is already loaded.
    func toggle(_ url: URL) {
        if currentURL == url, player != nil {
            isPlaying ? pause() : play()
            return
        }
        load(url)
    }

    func play() {
        guard let player, !isPlaying else { return }
        resume(player)
    }

    func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
        position = player.currentTime
        updateNowPlayingPlayback()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(seconds, 0), player.duration)
        player.currentTime = clamped
        position = clamped
        updateNowPlayingPlayback()
    }

    func stop() {
        ticker?.cancel()
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
        position = 0
        duration = 0
        resumeAfterInterruption = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Private

    private func load(_ url: URL) {
        stop()
        errorMessage = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = playerDelegate
            newPlayer.enableRate = true
            newPlayer.prepareToPlay()
            newPlayer.rate = rate
            player = newPlayer
            currentURL = url
            duration = newPlayer.duration
            publishNowPlayingItem()
            resume(newPlayer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resume(_ player: AVAudioPlayer) {
        try? AVAudioSession.sharedInstance().setActive(true)
        guard player.play() else {
            errorMessage = "Playback could not start."
            return
        }
        isPlaying = true
        resumeAfterInterruption = false
        updateNowPlayingPlayback()
        startTicker()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let player = self.player, self.isPlaying else { return }
                self.position = player.currentTime
            }
        }
    }

    private func didFinishPlaying() {
        ticker?.cancel()
        isPlaying = false
        position = 0
        player?.currentTime = 0
        updateNowPlayingPlayback()
    }

    // MARK: - Now Playing

    /// Sets the static metadata for a newly loaded file.
    private func publishNowPlayingItem() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTitle.map { displayTitle($0) } ?? "Phonon",
            MPMediaItemPropertyArtist: "Phonon",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Updates elapsed time and rate. The system extrapolates progress from
    /// these, so this only needs to run when playback state changes.
    private func updateNowPlayingPlayback() {
        let center = MPNowPlayingInfoCenter.default()
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(rate)
        center.nowPlayingInfo = info
    }

    // MARK: - Remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.isPlaying ? self.pause() : self.play()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.skip(by: Self.skipInterval)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.skip(by: -Self.skipInterval)
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, self.player != nil,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }

        center.changePlaybackRateCommand.supportedPlaybackRates = Self.rates.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, self.player != nil,
                  let event = event as? MPChangePlaybackRateCommandEvent
            else { return .commandFailed }
            self.setRate(event.playbackRate)
            return .success
        }

        // Single-file playback: no track list to move through.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    // MARK: - Audio session events

    private func observeAudioSession() {
        let notifications = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            MainActor.assumeIsolated {
                self?.handleInterruption(type: type, options: options)
            }
        })

        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                // Headphones unplugged or Bluetooth disconnected: pause rather than blast the speaker.
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        })
    }

    private func handleInterruption(
        type: AVAudioSession.InterruptionType?,
        options: AVAudioSession.InterruptionOptions
    ) {
        switch type {
        case .began:
            let wasPlaying = isPlaying
            pause()
            resumeAfterInterruption = wasPlaying
        case .ended:
            if resumeAfterInterruption, options.contains(.shouldResume) {
                play()
            }
            resumeAfterInterruption = false
        default:
            break
        }
    }
}

/// Forwards `AVAudioPlayer` completion to the controller.
private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (@MainActor () -> Void)?

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onFinish?() }
    }
}
