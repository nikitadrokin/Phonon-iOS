import SwiftUI

/// Voice, output, and model management.
struct SettingsView: View {
    @Bindable var store: ModelStore
    var exporter: ExportController
    var previewer: VoicePreviewer
    var playback: PlaybackController

    @AppStorage("outputFormat") private var formatRaw = AudioFileFormat.m4a.rawValue
    @AppStorage("paragraphPause") private var pauseSeconds = 0.4
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                outputSection
                modelSection
                aboutSection
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete the voice model?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await store.deleteModel() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the downloaded files from this device and frees the space. Speech stops working until you download it again (\(store.downloadSizeText)).")
            }
        }
    }

    private var voiceSection: some View {
        Section("Voice & Playback") {
            if store.voices.isEmpty {
                Text("Voices are available after the voice model is ready.")
                    .foregroundStyle(.secondary)
            } else {
                let voice = VoiceCatalog.info(for: store.selectedVoice)
                NavigationLink {
                    VoicePickerView(store: store, previewer: previewer, isLocked: exporter.isExporting)
                } label: {
                    HStack(spacing: 12) {
                        VoiceAvatar(voice: voice, size: 32)
                        Text("Voice")
                        Spacer()
                        Text(voice.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Picker("Playback Speed", selection: Binding(
                get: { playback.rate },
                set: { playback.setRate($0) }
            )) {
                ForEach(PlaybackController.rates, id: \.self) { Text(rateLabel($0)).tag($0) }
            }
        }
    }

    private var outputSection: some View {
        Section {
            Picker("Format", selection: $formatRaw) {
                ForEach(AudioFileFormat.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Pause between paragraphs")
                    Spacer()
                    Text(String(format: "%.1f s", pauseSeconds))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $pauseSeconds, in: 0...2, step: 0.1)
                    .accessibilityLabel("Pause between paragraphs")
            }
        } header: {
            Text("Output")
        } footer: {
            Text("Files are saved to the Phonon folder in the Files app. M4A is about a tenth the size of WAV.")
        }
    }

    private var modelSection: some View {
        Section {
            LabeledContent("Model", value: ModelConfiguration.displayName)
            LabeledContent("Status", value: statusText)
            if let source = ModelConfiguration.sourceDescription {
                LabeledContent("Source", value: source)
            }
            if let bytes = store.installedBytes {
                LabeledContent("Installed", value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
            modelActions
            if let error = store.updateError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if store.hasDownloadedFiles && !isDownloading {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(store.isInstalled ? "Delete Model" : "Delete Partial Download", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(exporter.isExporting)
            }
        } header: {
            Text("Voice Model")
        } footer: {
            Text(modelFooter)
        }
    }

    /// Download, progress, and update controls for the current model state.
    @ViewBuilder
    private var modelActions: some View {
        switch store.state {
        case let .downloading(fraction):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction)
                HStack {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel) { store.cancelDownload() }
                }
            }
        case let .failed(message) where !store.isInstalled:
            Text(message).font(.footnote).foregroundStyle(.red)
            downloadButton(title: "Retry Download")
        case .needsDownload, .notConfigured:
            downloadButton(title: "Download (\(store.downloadSizeText))")
            if !store.network.isConnected && ModelConfiguration.baseURL != nil {
                Text("You are offline. Connect to the internet to download.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        default:
            if store.updateAvailable {
                Button("Update Model") { store.download() }
                    .disabled(exporter.isExporting)
            } else if store.isInstalled {
                Button("Check for Update") { Task { await store.refreshRemote() } }
            }
        }
    }

    private func downloadButton(title: String) -> some View {
        Button {
            store.download()
        } label: {
            Label(title, systemImage: "arrow.down.circle")
        }
        .disabled(!store.canDownload)
    }

    private var isDownloading: Bool {
        if case .downloading = store.state { true } else { false }
    }

    private var modelFooter: String {
        if case .notConfigured = store.state {
            return "This build has no model download source. Set PHONON_MODEL_BASE_URL to the hosted Core ML export of \(ModelConfiguration.upstreamRepositoryID)."
        }
        return "Downloaded once from Hugging Face and stored on this device, not inside the app, so app updates never re-download it. Speech is generated fully offline."
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Engine", value: ModelConfiguration.displayName)
            LabeledContent("License", value: ModelConfiguration.licenseName)
            if let url = ModelConfiguration.upstreamPageURL {
                Link(destination: url) {
                    LabeledContent("Model page", value: ModelConfiguration.upstreamRepositoryID)
                }
            }
        } header: {
            Text("About")
        } footer: {
            if ModelConfiguration.isNonCommercial {
                Text("The \(ModelConfiguration.licenseName) license allows non-commercial use only.")
            }
        }
    }

    private var statusText: String {
        switch store.state {
        case .checking: "Checking"
        case .notConfigured: "Source not set"
        case .needsDownload: "Not downloaded"
        case .downloading: "Downloading"
        case .loading: "Loading"
        case .ready: store.updateAvailable ? "Ready (update available)" : "Ready"
        case .failed: "Problem"
        }
    }
}
