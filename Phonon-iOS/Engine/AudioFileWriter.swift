import AVFoundation
import Foundation

/// Output container for exported speech.
nonisolated enum AudioFileFormat: String, CaseIterable, Identifiable, Sendable {
    /// AAC in an MPEG-4 container. Small files, plays everywhere.
    case m4a
    /// 16-bit PCM. Larger, lossless relative to the model output.
    case wav

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a: "M4A (AAC)"
        case .wav: "WAV (16-bit)"
        }
    }

    var fileExtension: String { rawValue }

    /// `AVAudioFile` writing settings for mono audio at `sampleRate`.
    func settings(sampleRate: Double) -> [String: Any] {
        switch self {
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}

/// Failures while writing audio to disk.
nonisolated enum AudioFileWriterError: LocalizedError {
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .bufferAllocationFailed: "Could not allocate an audio buffer."
        }
    }
}

/// Appends mono Float32 sample chunks to an audio file as they arrive, so memory use does not
/// depend on the length of the audio.
///
/// `append` is safe to call from the engine's callback thread. The first write error is kept and
/// later writes are skipped; call `finish()` to close the file and surface it.
nonisolated final class AudioFileWriter: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let processingFormat: AVAudioFormat
    private let sampleRate: Double
    private var framesWritten: Int64 = 0
    private var failure: Error?

    init(url: URL, format: AudioFileFormat, sampleRate: Double) throws {
        self.url = url
        self.sampleRate = sampleRate
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings(sampleRate: sampleRate),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.file = file
        self.processingFormat = file.processingFormat
    }

    /// Frames written so far.
    var frames: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return framesWritten
    }

    /// Seconds of audio written so far.
    var seconds: Double { Double(frames) / sampleRate }

    /// The first write error, if any occurred.
    var firstFailure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    /// Appends `samples` (mono Float32 at the writer's sample rate).
    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard failure == nil, let file else { return }
        do {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            ), let channel = buffer.floatChannelData?[0] else {
                throw AudioFileWriterError.bufferAllocationFailed
            }
            samples.withUnsafeBufferPointer { source in
                if let base = source.baseAddress {
                    channel.update(from: base, count: samples.count)
                }
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            try file.write(from: buffer)
            framesWritten += Int64(samples.count)
        } catch {
            failure = error
        }
    }

    /// Appends `seconds` of silence in one-second pieces.
    func appendSilence(seconds: Double) {
        guard seconds > 0 else { return }
        var remaining = Int((seconds * sampleRate).rounded())
        let piece = [Float](repeating: 0, count: Int(sampleRate))
        while remaining > 0 {
            let count = min(remaining, piece.count)
            append(count == piece.count ? piece : Array(piece.prefix(count)))
            remaining -= count
        }
    }

    /// Closes the file so it is complete and playable, then throws the first write error if one
    /// occurred. Safe to call more than once.
    @discardableResult
    func finish() throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        if let failure { throw failure }
        return framesWritten
    }
}
