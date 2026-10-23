import SwiftUI

/// Voice, output, and model management.
struct SettingsView: View {
    @Bindable var store: ModelStore
    var exporter: ExportController
    var previewer: VoicePreviewer

    @AppStorage("outputFormat") private var formatRaw = AudioFileFormat.m4a.rawValue
    @AppStorage("paragraphPause") private var pauseSeconds = 0.4
    @AppStorage(ModelConfiguration.overrideDefaultsKey) private var hostOverride = ""
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
                Button("Delete Model", role: .destructive) {
                    Task { await store.deleteModel() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can download it again later.")
            }
        }
    }

    private var voiceSection: some View {
        Section("Voice") {
            if store.voices.isEmpty {
                Text("Available after the voice model is ready.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Voice", selection: Binding(
                    get: { store.selectedVoice },
                    set: { name in Task { await store.selectVoice(name) } }
                )) {
                    ForEach(store.voices, id: \.self) { Text($0).tag($0) }
                }
                .disabled(exporter.isExporting)

                Button {
                    if let phonon = store.phonon { previewer.toggle(using: phonon) }
                } label: {
                    Label(previewer.isPlaying ? "Stop Preview" : "Preview Voice",
                          systemImage: previewer.isPlaying ? "stop.fill" : "play.fill")
                }
                .disabled(exporter.isExporting || store.phonon == nil)
                if let message = previewer.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
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
            LabeledContent("Status", value: statusText)
            if let bytes = store.installedBytes {
                LabeledContent("Installed", value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
            if store.updateAvailable {
                Button("Update Model") { store.download() }
                    .disabled(exporter.isExporting)
            } else if store.isInstalled {
                Button("Check for Update") { Task { await store.refreshRemote() } }
            }
            if let error = store.updateError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if store.isInstalled {
                Button("Delete Model", role: .destructive) { confirmDelete = true }
                    .disabled(exporter.isExporting)
            }
            TextField("Model host URL", text: $hostOverride, prompt: Text(ModelConfiguration.buildSettingURLString.isEmpty ? "https://…" : ModelConfiguration.buildSettingURLString))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await store.refreshRemote() } }
        } header: {
            Text("Voice Model")
        } footer: {
            Text("The model is downloaded once and stored on this device, not inside the app, so app updates never re-download it. The host URL must serve the Core ML model folder with its bundle.json. Leave blank to use the app's built-in setting.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Engine", value: "Phonon 31m (English)")
            LabeledContent("License", value: "Apache 2.0")
        }
    }

    private var statusText: String {
        switch store.state {
        case .checking: "Checking"
        case .notConfigured: "Host not set"
        case .needsDownload: "Not downloaded"
        case .downloading: "Downloading"
        case .loading: "Loading"
        case .ready: store.updateAvailable ? "Ready (update available)" : "Ready"
        case .failed: "Problem"
        }
    }
}
