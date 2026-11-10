import Foundation
import PhononTTS
import Synchronization

/// Snapshot of an export in flight.
nonisolated struct ExportProgress: Sendable, Equatable {
    /// Paragraphs fully spoken.
    var completedParagraphs: Int
    /// Total paragraphs in the document.
    var totalParagraphs: Int
    /// Seconds of audio written so far.
    var audioSeconds: Double
    /// Wall-clock seconds since the export started.
    var elapsedSeconds: Double

    /// Audio seconds produced per wall-clock second.
    var realtimeFactor: Double { elapsedSeconds > 0 ? audioSeconds / elapsedSeconds : 0 }

    /// Fraction of paragraphs completed, 0...1.
    var fraction: Double {
        totalParagraphs > 0 ? Double(completedParagraphs) / Double(totalParagraphs) : 0
    }
}

/// Outcome of an export, including partial exports that were cancelled.
nonisolated struct ExportResult: Sendable {
    /// The audio file, or nil when nothing was written (the empty file is removed).
    let url: URL?
    let audioSeconds: Double
    let wallSeconds: Double
    let completedParagraphs: Int
    let totalParagraphs: Int
    let wasCancelled: Bool
    /// The paragraphs that made it into the audio, with their start times.
    let transcript: Transcript

    var realtimeFactor: Double { wallSeconds > 0 ? audioSeconds / wallSeconds : 0 }
}

nonisolated enum ExportError: LocalizedError {
    case emptyText

    var errorDescription: String? {
        switch self {
        case .emptyText: "There is no readable text to convert."
        }
    }
}

/// Speaks a document paragraph by paragraph and writes the audio to disk as it is generated.
nonisolated enum SpeechExporter {
    /// Exports `text` to `destination`.
    ///
    /// Cancelling the calling task stops generation at the next chunk, closes the file cleanly and
    /// returns a result with `wasCancelled == true`; the partial file stays playable. Other errors
    /// are rethrown after the file is closed (an empty file is removed).
    static func export(
        text: String,
        using phonon: Phonon,
        format: AudioFileFormat,
        pauseSeconds: Double,
        destination: URL,
        onProgress: @escaping @Sendable (ExportProgress) -> Void
    ) async throws -> ExportResult {
        let paragraphs = TextChunker.paragraphs(from: text)
        guard !paragraphs.isEmpty else { throw ExportError.emptyText }

        let writer = try AudioFileWriter(url: destination, format: format, sampleRate: Phonon.sampleRate)
        let clock = ContinuousClock()
        let start = clock.now
        let total = paragraphs.count
        let completed = Mutex(0)

        @Sendable func report() {
            let seconds = start.duration(to: clock.now)
            let elapsed = Double(seconds.components.seconds)
                + Double(seconds.components.attoseconds) / 1e18
            onProgress(ExportProgress(
                completedParagraphs: completed.withLock { $0 },
                totalParagraphs: total,
                audioSeconds: writer.seconds,
                elapsedSeconds: elapsed
            ))
        }

        // Report roughly every two seconds of generated audio (25 chunks of 80 ms).
        let chunkCounter = Mutex(0)
        var wasCancelled = false
        var thrown: Error?
        var segments: [Transcript.Segment] = []

        report()
        do {
            for (index, paragraph) in paragraphs.enumerated() {
                try Task.checkCancellation()
                segments.append(Transcript.Segment(id: index, start: writer.seconds, text: paragraph))
                try await phonon.speak(paragraph) { samples in
                    writer.append(samples)
                    let shouldReport = chunkCounter.withLock { count -> Bool in
                        count += 1
                        return count % 25 == 0
                    }
                    if shouldReport { report() }
                }
                if let failure = writer.firstFailure { throw failure }
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }
                completed.withLock { $0 += 1 }
                if index < total - 1 { writer.appendSilence(seconds: pauseSeconds) }
                report()
            }
        } catch is CancellationError {
            wasCancelled = true
        } catch {
            if Task.isCancelled { wasCancelled = true } else { thrown = error }
        }

        let finishError: Error?
        do {
            try writer.finish()
            finishError = nil
        } catch {
            finishError = error
        }

        let hasAudio = writer.frames > 0
        if !hasAudio { try? FileManager.default.removeItem(at: destination) }
        if let error = thrown ?? finishError { throw error }

        let wall = start.duration(to: clock.now)
        return ExportResult(
            url: hasAudio ? destination : nil,
            audioSeconds: writer.seconds,
            wallSeconds: Double(wall.components.seconds) + Double(wall.components.attoseconds) / 1e18,
            completedParagraphs: completed.withLock { $0 },
            totalParagraphs: total,
            wasCancelled: wasCancelled,
            // A paragraph cancelled before any of its audio was written is left out.
            transcript: Transcript(segments: segments.filter { ($0.start ?? 0) < writer.seconds })
        )
    }
}
