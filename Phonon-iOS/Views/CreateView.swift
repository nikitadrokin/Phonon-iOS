import SwiftUI
import UniformTypeIdentifiers

/// Text input plus the generate/stop controls.
struct CreateView: View {
    @Bindable var store: ModelStore
    @Bindable var exporter: ExportController
    var playback: PlaybackController
    var library: ExportLibrary
    var openSettings: () -> Void
    var openLibrary: () -> Void

    @AppStorage("outputFormat") private var formatRaw = AudioFileFormat.m4a.rawValue
    @AppStorage("paragraphPause") private var pauseSeconds = 0.4

    @State private var text = ""
    @State private var showImporter = false
    @State private var importError: String?
    @FocusState private var editorFocused: Bool

    private var format: AudioFileFormat { AudioFileFormat(rawValue: formatRaw) ?? .m4a }
    private var canGenerate: Bool {
        store.state == .ready && !exporter.isExporting && !trimmedText.isEmpty
    }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ModelStatusCard(store: store, openSettings: openSettings)
                editor
                statsRow
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .navigationTitle("Phonon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: Self.importTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Could not import", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert("Export problem", isPresented: Binding(
                get: { exporter.errorMessage != nil },
                set: { if !$0 { exporter.dismissError() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exporter.errorMessage ?? "")
            }
        }
    }

    // MARK: - Pieces

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($editorFocused)
                .disabled(exporter.isExporting)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Text to convert to audio")
            if text.isEmpty {
                Text("Paste an essay or article, or import a text file.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
    }

    private var statsRow: some View {
        HStack {
            let words = TextChunker.wordCount(in: text)
            Text("\(words.formatted()) words")
            Spacer()
            if words > 0 {
                // Rough estimate at about 150 words per minute; measured after the first export.
                Text("≈ \(Duration.seconds(Double(words) / 150 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))) of audio")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if exporter.isExporting {
                progressPanel
            } else if let result = exporter.lastResult {
                resultPanel(result)
            }
            actionBar
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.default, value: exporter.isExporting)
    }

    private var progressPanel: some View {
        let progress = exporter.progress
        return VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress?.fraction ?? 0)
            HStack {
                Text("Paragraph \(min((progress?.completedParagraphs ?? 0) + 1, progress?.totalParagraphs ?? 1)) of \(progress?.totalParagraphs ?? 0)")
                Spacer()
                Text(Self.clock(progress?.audioSeconds ?? 0))
                Text("·")
                Text(String(format: "%.1f× real time", progress?.realtimeFactor ?? 0))
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            Text("Keep the app open and the screen on while generating.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .controlSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    private func resultPanel(_ result: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = result.url {
                Label(
                    result.wasCancelled
                        ? "Stopped. Saved \(Self.clock(result.audioSeconds)) of audio"
                        : "Done. \(Self.clock(result.audioSeconds)) of audio",
                    systemImage: result.wasCancelled ? "stop.circle" : "checkmark.circle"
                )
                .font(.headline)
                Text(String(format: "Generated in %.0f s (%.1f× real time).", result.wallSeconds, result.realtimeFactor))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if exporter.stoppedInBackground {
                    Text("Generation stopped because the app left the foreground. The partial audio is saved.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button {
                        playback.toggle(url)
                    } label: {
                        Label(playback.currentURL == url && playback.isPlaying ? "Pause" : "Play",
                              systemImage: playback.currentURL == url && playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button("Library", action: openLibrary)
                    Spacer()
                    Button {
                        exporter.dismissResult()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Dismiss")
                }
                .adaptiveButtonStyle()
            } else {
                Label("Nothing was generated", systemImage: "info.circle")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .controlSurface(cornerRadius: 20)
    }

    private var actionBar: some View {
        AdaptiveGlassContainer(spacing: 12) {
            HStack(spacing: 12) {
                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.joined(separator: "\n\n")
                    guard !pasted.isEmpty else { return }
                    Task { @MainActor in text = pasted }
                }
                .buttonBorderShape(.capsule)
                .disabled(exporter.isExporting)

                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "doc.badge.plus")
                }
                .adaptiveButtonStyle()
                .disabled(exporter.isExporting)

                Spacer(minLength: 0)

                if exporter.isExporting {
                    Button(role: .destructive) {
                        exporter.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .adaptiveButtonStyle(prominent: true)
                    .tint(.red)
                } else {
                    Button {
                        generate()
                    } label: {
                        Label("Generate", systemImage: "waveform")
                    }
                    .adaptiveButtonStyle(prominent: true)
                    .disabled(!canGenerate)
                }
            }
            .controlSize(.large)
        }
    }

    // MARK: - Actions

    private func generate() {
        guard let phonon = store.phonon else { return }
        editorFocused = false
        playback.stop()
        exporter.start(
            text: text,
            phonon: phonon,
            format: format,
            pauseSeconds: pauseSeconds
        ) {
            Task { await library.reload() }
        }
    }

    private static let importTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text, .utf8PlainText]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }()

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            importError = error.localizedDescription
        case let .success(urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    text = try await TextImporter.read(url)
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    private static func clock(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }
}

/// Reads text files chosen in the document picker.
nonisolated enum TextImporter {
    /// Largest file accepted, to keep the editor responsive.
    static let maxBytes = 5 * 1_024 * 1_024

    enum ImportError: LocalizedError {
        case tooLarge
        case unreadable
        case noAccess

        var errorDescription: String? {
            switch self {
            case .tooLarge: "The file is larger than 5 MB."
            case .unreadable: "The file is not readable text."
            case .noAccess: "The app was not allowed to open the file."
            }
        }
    }

    static func read(_ url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard url.startAccessingSecurityScopedResource() else { throw ImportError.noAccess }
            defer { url.stopAccessingSecurityScopedResource() }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maxBytes else { throw ImportError.tooLarge }
            var encoding = String.Encoding.utf8
            guard let text = try? String(contentsOf: url, usedEncoding: &encoding) else {
                throw ImportError.unreadable
            }
            return text
        }.value
    }
}
