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
                .onChange(of: text) { _, newValue in
                    // Writing something new turns the result card back into the Generate button.
                    // Clearing the editor (including the automatic clear after an export) does not.
                    let isDirty = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if isDirty, !exporter.isExporting, exporter.lastResult != nil {
                        exporter.dismissResult()
                    }
                }
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
            .softScrollEdgeEffect()
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

    /// What the bottom surface shows. One glass surface morphs between these states:
    /// Generate button → progress card → result card, and back to the button once the text is
    /// edited again.
    private enum BottomPhase: Hashable {
        case hidden, generate, generating, result
    }

    private var bottomPhase: BottomPhase {
        if exporter.isExporting { return .generating }
        if exporter.lastResult != nil { return .result }
        if !trimmedText.isEmpty { return .generate }
        return .hidden
    }

    private var bottomPanel: some View {
        let phase = bottomPhase
        return VStack {
            if phase != .hidden {
                ZStack {
                    switch phase {
                    case .generate, .hidden:
                        generateButton
                            .transition(.blurReplace)
                    case .generating:
                        progressContent
                            .padding(16)
                            .transition(.blurReplace)
                    case .result:
                        if let result = exporter.lastResult {
                            resultContent(result)
                                .padding(16)
                                .transition(.blurReplace)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .morphingSurface(prominent: phase == .generate)
                .transition(.scale(0.9, anchor: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.4), value: phase)
    }

    private var generateButton: some View {
        Button(action: generate) {
            Label("Generate Audio", systemImage: "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
        .opacity(canGenerate ? 1 : 0.5)
    }

    private var estimatedDuration: String {
        // Roughly 150 words a minute at 1×.
        Duration.seconds(max(Double(wordCount) / 150 * 60, 60))
            .formatted(.units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2))
    }

    // MARK: - Generating

    private var progressContent: some View {
        let progress = exporter.progress
        let fraction = progress?.fraction ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generating Audio")
                        .font(.headline)
                    Text(progressDetail(progress))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    exporter.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .adaptiveButtonStyle()
                .buttonBorderShape(.circle)
                .tint(.red)
                .accessibilityLabel("Stop Generating")
                .accessibilityHint("Keeps the audio made so far")
            }

            ProgressView(value: fraction)
                .animation(.smooth, value: fraction)

            HStack {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: fraction))
                Spacer()
                Text("Keep Phonon open until it finishes")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func progressDetail(_ progress: ExportProgress?) -> String {
        guard let progress, progress.totalParagraphs > 0 else { return "Preparing…" }
        let paragraph = min(progress.completedParagraphs + 1, progress.totalParagraphs)
        let speed = progress.realtimeFactor.formatted(.number.precision(.fractionLength(1)))
        return "Paragraph \(paragraph) of \(progress.totalParagraphs) · \(speed)× real time"
    }

    // MARK: - Finished

    private func resultContent(_ result: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: resultSymbol(result))
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(result.url != nil && !result.wasCancelled ? Color.green : Color.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(resultTitle(result))
                        .font(.headline)
                    Text(resultDetail(result))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if exporter.stoppedInBackground {
                        Text("Phonon left the foreground, so generation stopped. The audio so far is saved.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                Button {
                    exporter.dismissResult()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.fill.tertiary, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            if let url = result.url {
                resultActions(url)
            }
        }
    }

    private func resultActions(_ url: URL) -> some View {
        let isThis = playback.currentURL == url
        let isPlaying = isThis && playback.isPlaying
        let playTitle = isPlaying ? "Pause" : (isThis && playback.position > 0 ? "Resume" : "Play")
        return HStack(spacing: 10) {
            Button {
                playback.toggle(url)
            } label: {
                Label(playTitle, systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .contentTransition(.symbolEffect(.replace))
            }
            .adaptiveButtonStyle(prominent: true)

            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 24)
            }
            .adaptiveButtonStyle()
            .accessibilityLabel("Share")

            Button(action: openLibrary) {
                Image(systemName: "music.note.list")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 24)
            }
            .adaptiveButtonStyle()
            .accessibilityLabel("Show in Library")
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private func resultSymbol(_ result: ExportResult) -> String {
        if result.url == nil { return "exclamationmark.circle.fill" }
        return result.wasCancelled ? "stop.circle.fill" : "checkmark.circle.fill"
    }

    private func resultTitle(_ result: ExportResult) -> String {
        if result.url == nil { return "Nothing Was Generated" }
        return result.wasCancelled ? "Stopped Early" : "Audio Ready"
    }

    private func resultDetail(_ result: ExportResult) -> String {
        guard let url = result.url else { return "Generation stopped before any audio was written." }
        if playback.currentURL == url {
            return "\(clockText(playback.position)) of \(clockText(result.audioSeconds))"
        }
        let made = Duration.seconds(result.wallSeconds.rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        return "\(clockText(result.audioSeconds)) long · made in \(made)"
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
            // The text lives on in the saved transcript, so a finished export clears the editor.
            // A stopped or failed one keeps it, so the rest can be generated again.
            if let result = exporter.lastResult, result.url != nil, !result.wasCancelled {
                text = ""
            }
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
