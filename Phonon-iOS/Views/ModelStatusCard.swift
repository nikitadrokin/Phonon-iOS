import SwiftUI

/// Shows what the voice model needs from the user: download, wait, or retry. Hidden once ready.
struct ModelStatusCard: View {
    @Bindable var store: ModelStore
    var openSettings: () -> Void

    var body: some View {
        switch store.state {
        case .ready:
            EmptyView()
        default:
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            .confirmationDialog(
                "Download over a metered connection?",
                isPresented: $store.needsCellularConfirmation,
                titleVisibility: .visible
            ) {
                Button("Download Now") { store.download(allowCellular: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You are not on Wi-Fi. The voice model is \(sizeText).")
            }
        }
    }

    private var sizeText: String {
        if let bytes = store.remote?.totalBytes {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return "about 160 MB"
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .checking:
            Label {
                Text("Checking voice model…")
            } icon: {
                ProgressView()
            }
        case .notConfigured:
            Label("Voice model host not set", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("Enter the URL of the hosted Core ML model folder in Settings to download the voice model.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings", action: openSettings)
                .adaptiveButtonStyle()
        case .needsDownload:
            Label("Download the voice model", systemImage: "arrow.down.circle")
                .font(.headline)
            Text("One-time download of \(sizeText). It is stored on this device outside the app, so app updates do not download it again, and speech is generated fully offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !store.network.isConnected {
                Text("You are offline. Connect to the internet to download.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button("Download (\(sizeText))") { store.download() }
                .adaptiveButtonStyle(prominent: true)
                .disabled(!store.network.isConnected)
        case let .downloading(fraction):
            Label("Downloading voice model", systemImage: "arrow.down.circle")
                .font(.headline)
            ProgressView(value: fraction)
            HStack {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { store.cancelDownload() }
                    .adaptiveButtonStyle()
            }
            Text("Stopping keeps finished files, so the next attempt resumes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .loading(compiling):
            Label {
                Text(compiling ? "Preparing the model for this device…" : "Loading voice model…")
            } icon: {
                ProgressView()
            }
            .font(.headline)
            if compiling {
                Text("This happens once after install or a model update and takes about 10 seconds or more.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case let .failed(message):
            Label("Voice model problem", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Try Again") {
                    if store.isInstalled {
                        Task { await store.reload() }
                    } else {
                        store.download()
                    }
                }
                .adaptiveButtonStyle(prominent: true)
                Button("Re-download") {
                    Task {
                        await store.deleteModel()
                        store.download()
                    }
                }
                .adaptiveButtonStyle()
            }
        case .ready:
            EmptyView()
        }
    }
}
