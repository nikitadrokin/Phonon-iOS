import AVFoundation
import Foundation
import Observation

/// One exported audio file.
nonisolated struct ExportItem: Identifiable, Hashable, Sendable {
    let url: URL
    let date: Date
    let bytes: Int64
    let duration: Double

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Lists, and deletes, the files in the exports folder.
@MainActor @Observable
final class ExportLibrary {
    private(set) var items: [ExportItem] = []
    private(set) var isLoading = false

    func reload() async {
        isLoading = true
        items = await Task.detached(priority: .utility) { Self.scan() }.value
        isLoading = false
    }

    func delete(_ item: ExportItem) {
        try? FileManager.default.removeItem(at: item.url)
        TranscriptStore.delete(for: item.url)
        items.removeAll { $0.id == item.id }
    }

    private nonisolated static func scan() -> [ExportItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: ExportController.exportsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { ["m4a", "wav"].contains($0.pathExtension.lowercased()) }
            .compactMap { url -> ExportItem? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let duration: Double = (try? AVAudioFile(forReading: url)).map {
                    $0.processingFormat.sampleRate > 0 ? Double($0.length) / $0.processingFormat.sampleRate : 0
                } ?? 0
                return ExportItem(
                    url: url,
                    date: values?.contentModificationDate ?? .distantPast,
                    bytes: Int64(values?.fileSize ?? 0),
                    duration: duration
                )
            }
            .sorted { $0.date > $1.date }
    }
}
