import SwiftUI

/// Exported files with playback, sharing and deletion. Files also appear in the Files app.
struct LibraryView: View {
    var library: ExportLibrary
    var playback: PlaybackController

    var body: some View {
        NavigationStack {
            Group {
                if library.items.isEmpty {
                    VStack(spacing: 0) {
                        ScrollingTitle("Library")
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        if library.isLoading {
                            ProgressView()
                                .frame(maxHeight: .infinity)
                        } else {
                            ContentUnavailableView(
                                "No Recordings Yet",
                                systemImage: "waveform",
                                description: Text("Audio you create appears here and in the Files app.")
                            )
                        }
                    }
                } else {
                    List {
                        ScrollingTitle("Library")
                        ForEach(library.items) { item in
                            LibraryRow(item: item, playback: playback)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    ShareLink(item: item.url)
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .softScrollEdgeEffect()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task { await library.reload() }
            .refreshable { await library.reload() }
            .legacyNowPlayingInset(playback: playback)
            .animation(.snappy, value: playback.currentURL)
        }
    }

    private func delete(_ item: ExportItem) {
        if playback.currentURL == item.url { playback.stop() }
        library.delete(item)
    }
}

private struct LibraryRow: View {
    let item: ExportItem
    var playback: PlaybackController

    private var isCurrent: Bool { playback.currentURL == item.url }
    private var isPlaying: Bool { isCurrent && playback.isPlaying }

    var body: some View {
        Button {
            playback.toggle(item.url)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                    Image(systemName: isPlaying ? "waveform" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle(item.name))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(clockText(item.duration))
                            .monospacedDigit()
                        Text("·")
                        Text(item.date, format: .relative(presentation: .named))
                        Text("·")
                        Text(item.url.pathExtension.uppercased())
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel("\(displayTitle(item.name)), \(clockText(item.duration))")
        .accessibilityHint(isPlaying ? "Pauses playback" : "Plays this recording")
    }
}
