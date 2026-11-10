import Foundation

/// The text an export was generated from, one segment per spoken paragraph.
///
/// PhononTTS reports no word timings, but the exporter speaks one paragraph per call, so the
/// audio position at the start of each call is an exact paragraph timestamp. Older exports have
/// no transcript at all; edits that change the paragraph count drop the timings.
nonisolated struct Transcript: Codable, Sendable, Equatable {
    struct Segment: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        /// Seconds into the audio where this paragraph starts, or nil when unknown.
        var start: Double?
        var text: String
    }

    var version = 1
    var segments: [Segment]

    /// True when every segment has a start time, so playback can follow and seek by paragraph.
    var isTimed: Bool { !segments.isEmpty && segments.allSatisfy { $0.start != nil } }

    /// Paragraphs separated by blank lines, as shown in the editor.
    var text: String { segments.map(\.text).joined(separator: "\n\n") }

    /// Index of the paragraph being spoken at `seconds`.
    func segmentIndex(at seconds: Double) -> Int? {
        guard isTimed else { return nil }
        return segments.lastIndex { ($0.start ?? 0) <= seconds + 0.05 } ?? 0
    }

    /// Replaces the text. Timings survive when the paragraph count is unchanged.
    func edited(_ newText: String) -> Transcript {
        let paragraphs = newText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let keepsTimes = isTimed && paragraphs.count == segments.count
        return Transcript(segments: paragraphs.enumerated().map { index, text in
            Segment(id: index, start: keepsTimes ? segments[index].start : nil, text: text)
        })
    }
}

/// Saves transcripts in Application Support, keyed by audio file name, so the Exports folder
/// shared with the Files app holds only audio.
nonisolated enum TranscriptStore {
    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Transcripts", directoryHint: .isDirectory)
    }

    private static func fileURL(for audioURL: URL) -> URL {
        directory.appending(path: audioURL.lastPathComponent).appendingPathExtension("json")
    }

    /// The transcript for `audioURL`, or nil for exports made before transcripts were saved.
    static func load(for audioURL: URL) -> Transcript? {
        guard let data = try? Data(contentsOf: fileURL(for: audioURL)) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    static func save(_ transcript: Transcript, for audioURL: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(transcript)
        try data.write(to: fileURL(for: audioURL), options: .atomic)
    }

    static func delete(for audioURL: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: audioURL))
    }
}
