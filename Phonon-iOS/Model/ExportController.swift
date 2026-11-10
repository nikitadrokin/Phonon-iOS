import Foundation
import Observation
import PhononTTS
import UIKit

/// Runs one export at a time: owns the generation task, keeps the screen awake, and stops
/// cleanly (partial file kept) if iOS is about to suspend the app.
@MainActor @Observable
final class ExportController {
    private(set) var isExporting = false
    private(set) var progress: ExportProgress?
    private(set) var lastResult: ExportResult?
    private(set) var errorMessage: String?
    /// True when the last export ended early because the app left the foreground.
    private(set) var stoppedInBackground = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// Directory the exports live in. It is shared with the Files app.
    nonisolated static var exportsDirectory: URL {
        URL.documentsDirectory.appending(path: "Exports", directoryHint: .isDirectory)
    }

    /// Starts exporting `text`. Does nothing if an export is already running.
    func start(
        text: String,
        phonon: Phonon,
        format: AudioFileFormat,
        pauseSeconds: Double,
        onFinished: @escaping @MainActor () -> Void
    ) {
        guard !isExporting else { return }
        let destination: URL
        do {
            destination = try Self.makeDestination(for: text, format: format)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isExporting = true
        progress = nil
        lastResult = nil
        errorMessage = nil
        stoppedInBackground = false
        UIApplication.shared.isIdleTimerDisabled = true
        beginBackgroundGrace()

        task = Task { [weak self] in
            do {
                let result = try await SpeechExporter.export(
                    text: text,
                    using: phonon,
                    format: format,
                    pauseSeconds: pauseSeconds,
                    destination: destination
                ) { update in
                    Task { @MainActor in self?.progress = update }
                }
                if let url = result.url, !result.transcript.segments.isEmpty {
                    try? TranscriptStore.save(result.transcript, for: url)
                }
                self?.lastResult = result
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.finish()
            onFinished()
        }
    }

    /// Stops generation; the audio produced so far is saved.
    func stop() { task?.cancel() }

    func dismissError() { errorMessage = nil }

    func dismissResult() { lastResult = nil }

    // MARK: - Private

    private func finish() {
        isExporting = false
        task = nil
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundGrace()
    }

    /// Core ML cannot be relied on after suspension, so when the grace period ends the export is
    /// stopped (and the partial file closed) instead of being left to freeze mid-write.
    private func beginBackgroundGrace() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "phonon-export") { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isExporting else { return }
                self.stoppedInBackground = true
                self.task?.cancel()
            }
        }
    }

    private func endBackgroundGrace() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private static func makeDestination(for text: String, format: AudioFileFormat) throws -> URL {
        let directory = exportsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(
            .verbatim(
                "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: .current,
                calendar: .current
            )
        )
        return directory
            .appending(path: "\(title(from: text))-\(stamp)")
            .appendingPathExtension(format.fileExtension)
    }

    /// A filesystem-safe title from the first words of the text.
    private static func title(from text: String) -> String {
        let firstLine = TextChunker.paragraphs(from: text).first ?? "Audio"
        let words = firstLine.split(separator: " ").prefix(6).joined(separator: " ")
        let allowed = words.unicodeScalars.filter { $0.properties.isAlphabetic || $0.properties.numericType != nil || $0 == " " }
        let cleaned = String(String.UnicodeScalarView(allowed))
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty ? "Audio" : String(cleaned.prefix(48))
    }
}
