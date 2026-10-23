import SwiftUI

/// Exported files with playback, sharing and deletion. Files also appear in the Files app.
struct LibraryView: View {
    var library: ExportLibrary
    var playback: PlaybackController

    var body: some View {
        NavigationStack {
            Group {
                if library.items.isEmpty {
                    ContentUnavailableView(
                        library.isLoading ? "Loading…" : "No Audio Yet",
                        systemImage: "waveform",
                        description: Text("Generated audio files appear here and in the Files app under Phonon.")
                    )
                } else {
                    List {
                        ForEach(library.items) { item in
                            LibraryRow(item: item, playback: playback)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if playback.currentURL == item.url { playback.stop() }
                                        library.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .task { await library.reload() }
            .refreshable { await library.reload() }
        }
    }
}

private struct LibraryRow: View {
    let item: ExportItem
    var playback: PlaybackController

    private var isCurrent: Bool { playback.currentURL == item.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                ShareLink(item: item.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share \(item.name)")
                Button {
                    playback.toggle(item.url)
                } label: {
                    Image(systemName: isCurrent && playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCurrent && playback.isPlaying ? "Pause" : "Play")
            }
            if isCurrent {
                Slider(
                    value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }),
                    in: 0...max(playback.duration, 1)
                )
                HStack {
                    Text(Self.clock(playback.position))
                    Spacer()
                    Text(Self.clock(playback.duration))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            if isCurrent, let message = playback.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
        return [Self.clock(item.duration), size, item.date.formatted(date: .abbreviated, time: .shortened)]
            .joined(separator: " · ")
    }

    private static func clock(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }
}
