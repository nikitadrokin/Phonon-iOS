import SwiftUI
import UniformTypeIdentifiers

/// A full-page writing surface, like Apple Notes, with a floating generate bar.
struct CreateView: View {
    @Bindable var store: ModelStore
    @Bindable var exporter: ExportController
    var playback: PlaybackController
    var library: ExportLibrary
    var previewer: VoicePreviewer
    var openSettings: () -> Void
    var openLibrary: () -> Void

    @AppStorage("outputFormat") private var formatRaw = AudioFileFormat.m4a.rawValue
    @AppStorage("paragraphPause") private var pauseSeconds = 0.4

    @State private var text = ""
    @State private var showImporter = false
    @State private var showVoices = false
    @State private var importError: String?
    @FocusState private var editorFocused: Bool

    private var format: AudioFileFormat { AudioFileFormat(rawValue: formatRaw) ?? .m4a }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canGenerate: Bool {
        store.state == .ready && !exporter.isExporting && !trimmedText.isEmpty
    }
    private var wordCount: Int { TextChunker.wordCount(in: text) }

    var body: some View {
        NavigationStack {
            editor
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .top, spacing: 0) {
                    if store.state != .ready {
                        ModelStatusCard(store: store, openSettings: openSettings)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
                .navigationTitle(wordCount == 1 ? "1 word" : "\(wordCount.formatted()) words")
                .subtitle(wordCount == 0 ? nil : "About \(estimatedDuration)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(isPresented: $showVoices) {
                    VoicePickerView(store: store, previewer: previewer, isLocked: exporter.isExporting)
                }
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: Self.importTypes,
                    allowsMultipleSelection: false
                ) { result in
                    handleImport(result)
                }
                .alert("Could Not Import", isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(importError ?? "")
                }
                .alert("Export Problem", isPresented: Binding(
                    get: { exporter.errorMessage != nil },
                    set: { if !$0 { exporter.dismissError() } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(exporter.errorMessage ?? "")
                }
        }
    }

    // MARK: - Editor

    private var editor: some View {
        TextEditor(text: $text)
            .focused($editorFocused)
            .font(.body)
            .lineSpacing(5)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.horizontal, 15, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .disabled(exporter.isExporting)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Start writing")
                            .font(.title2.weight(.bold))
                        Text("Paste an article, essay or chapter — or import a text file — and Phonon will read it aloud.")
                            .font(.body)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Text to convert to audio")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            voiceButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                        text = text.isEmpty ? pasted : text + "\n\n" + pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import Text File", systemImage: "doc.badge.plus")
                }
                Divider()
                Button(role: .destructive) {
                    text = ""
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(text.isEmpty)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .disabled(exporter.isExporting)
        }
    }

    private var voiceButton: some View {
        let voice = VoiceCatalog.info(for: store.selectedVoice)
        return Button {
            editorFocused = false
            showVoices = true
        } label: {
            HStack(spacing: 8) {
                VoiceAvatar(voice: voice, size: 24)
                Text(store.selectedVoice.isEmpty ? "Voice" : voice.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 4)
        }
        .disabled(store.voices.isEmpty)
        .accessibilityLabel("Voice: \(voice.displayName)")
        .accessibilityHint("Choose a different voice")
    }

    // MARK: - Bottom

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if exporter.isExporting {
                progressPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let result = exporter.lastResult {
                resultPanel(result)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            actionBar
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.snappy, value: exporter.isExporting)
        .animation(.snappy, value: exporter.lastResult == nil)
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            if exporter.isExporting {
                Button(role: .destructive) {
                    exporter.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .fontWeight(.semibold)
                }
                .adaptiveButtonStyle(prominent: true)
                .tint(.red)
            } else if !trimmedText.isEmpty {
                Button {
                    generate()
                } label: {
                    Label("Generate", systemImage: "waveform")
                        .fontWeight(.semibold)
                }
                .adaptiveButtonStyle(prominent: true)
                .disabled(!canGenerate)
                .transition(.scale(0.8, anchor: .trailing).combined(with: .opacity))
            }
        }
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
        .animation(.snappy, value: trimmedText.isEmpty)
    }

    private var estimatedDuration: String {
        // Roughly 150 words a minute at 1×.
        Duration.seconds(max(Double(wordCount) / 150 * 60, 60))
            .formatted(.units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2))
    }

    private var progressPanel: some View {
        let progress = exporter.progress
        let done = progress?.completedParagraphs ?? 0
        let total = progress?.totalParagraphs ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Generating", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .symbolEffect(.variableColor.iterative)
                Spacer()
                Text(progress?.fraction ?? 0, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: progress?.fraction ?? 0)
            Text(total > 0
                 ? "Paragraph \(min(done + 1, total)) of \(total) · \(clockText(progress?.audioSeconds ?? 0)) of audio · \(String(format: "%.1f", progress?.realtimeFactor ?? 0))× real time"
                 : "Preparing…")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("Keep Phonon open until it finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .controlSurface(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    private func resultPanel(_ result: ExportResult) -> some View {
        HStack(spacing: 12) {
            if let url = result.url {
                let isThis = playback.currentURL == url
                let isPlaying = isThis && playback.isPlaying
                Button {
                    playback.toggle(url)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.tint, in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.wasCancelled ? "Stopped early" : "Ready to listen")
                        .font(.subheadline.weight(.semibold))
                    Text(isThis
                         ? "\(clockText(playback.position)) / \(clockText(result.audioSeconds))"
                         : "\(clockText(result.audioSeconds)) · made in \(Int(result.wallSeconds.rounded())) s")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if exporter.stoppedInBackground {
                        Text("Phonon left the foreground; the audio so far is saved.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)

                SpeedMenu(playback: playback) {
                    Text(rateLabel(playback.rate))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 40, minHeight: 32)
                }

                Menu {
                    ShareLink(item: url)
                    Button(action: openLibrary) {
                        Label("Show in Library", systemImage: "waveform")
                    }
                    Divider()
                    Button {
                        exporter.dismissResult()
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("More")
            } else {
                Label("Nothing was generated", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    exporter.dismissResult()
                } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .controlSurface(cornerRadius: 28)
    }

    // MARK: - Actions

    private func generate() {
        guard let phonon = store.phonon else { return }
        editorFocused = false
        playback.stop()
        previewer.stop()
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
