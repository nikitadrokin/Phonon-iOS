import Foundation
import Network
import Observation
import PhononTTS
import Synchronization

/// Tracks whether the current network path is metered (cellular or Personal Hotspot).
@MainActor @Observable
final class NetworkMonitor {
    private(set) var isExpensive = false
    private(set) var isConnected = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isExpensive = expensive
                self?.isConnected = connected
            }
        }
        monitor.start(queue: DispatchQueue(label: "phonon.network-monitor", qos: .utility))
    }

    deinit { monitor.cancel() }
}

/// Owns the on-device model: first-run download into Application Support (never bundled in the
/// app), compile/load, voice selection and updates.
///
/// The `Phonon` instance is loaded once and kept for the life of the store.
@MainActor @Observable
final class ModelStore {
    enum State: Equatable {
        /// Looking at what is installed.
        case checking
        /// The build has no model download source.
        case notConfigured
        /// Nothing installed yet.
        case needsDownload
        /// Downloading, fraction 0...1.
        case downloading(Double)
        /// Loading; `compiling` is true on the first load after an install or update.
        case loading(compiling: Bool)
        case ready
        case failed(String)
    }

    private(set) var state: State = .checking
    private(set) var phonon: Phonon?
    private(set) var voices: [String] = []
    private(set) var selectedVoice: String = ""
    /// Manifest of the hosted model, when reachable.
    private(set) var remote: ModelManifestSummary?
    /// True when the hosted model differs from the installed one.
    private(set) var updateAvailable = false
    /// Set when an update failed but the installed model still works.
    private(set) var updateError: String?
    /// Set when a download is requested on a metered connection and needs confirmation.
    var needsCellularConfirmation = false

    let network = NetworkMonitor()

    private static let voiceDefaultsKey = "selectedVoice"
    private var downloadTask: Task<Void, Never>?
    private var started = false

    var isInstalled: Bool { PhononModels.isInstalled() }

    /// Download size for display: exact once the host manifest is known, otherwise an estimate.
    var downloadSizeText: String {
        if let bytes = remote?.totalBytes {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return "a couple hundred MB"
    }

    /// True when a download can start now: a source is set, nothing is installed or running, and
    /// the device is online.
    var canDownload: Bool {
        guard ModelConfiguration.baseURL != nil, network.isConnected else { return false }
        switch state {
        case .needsDownload, .failed: return !isInstalled
        default: return false
        }
    }

    var installedBytes: Int64? {
        ModelManifestSummary.installed(at: PhononModels.defaultDirectory)?.totalBytes
    }

    /// Initial check; call once at launch.
    func start() async {
        guard !started else { return }
        started = true
        if isInstalled {
            await loadModels()
            await refreshRemote()
        } else {
            await refreshRemote()
            if case .checking = state { state = .needsDownload }
        }
    }

    /// Re-reads the hosted manifest and updates `updateAvailable`.
    func refreshRemote() async {
        guard let base = ModelConfiguration.baseURL else {
            remote = nil
            updateAvailable = false
            switch state {
            case .checking, .needsDownload:
                if !isInstalled { state = .notConfigured }
            default:
                break
            }
            return
        }
        if case .notConfigured = state, !isInstalled { state = .needsDownload }
        do {
            let manifest = try await ModelManifestSummary.fetch(from: base)
            remote = manifest
            let installedBuilt = ModelManifestSummary.installed(at: PhononModels.defaultDirectory)?.built
            updateAvailable = installedBuilt.map { $0 != manifest.built } ?? false
        } catch {
            remote = nil
        }
    }

    /// Starts the download. On a metered connection this asks for confirmation first unless
    /// `allowCellular` is true.
    func download(allowCellular: Bool = false) {
        guard downloadTask == nil else { return }
        guard let base = ModelConfiguration.baseURL else {
            state = .notConfigured
            return
        }
        if network.isExpensive && !allowCellular {
            needsCellularConfirmation = true
            return
        }
        downloadTask = Task { [weak self] in
            await self?.runDownload(from: base)
            self?.downloadTask = nil
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    /// Deletes the installed model and returns to the not-downloaded state.
    func deleteModel() async {
        downloadTask?.cancel()
        phonon = nil
        voices = []
        try? FileManager.default.removeItem(at: PhononModels.defaultDirectory)
        updateAvailable = false
        state = ModelConfiguration.baseURL == nil ? .notConfigured : .needsDownload
        await refreshRemote()
    }

    /// Switches the speaking voice and remembers the choice.
    func selectVoice(_ name: String) async {
        guard let phonon, voices.contains(name) else { return }
        do {
            if phonon.voice != name { try await phonon.setVoice(name) }
            selectedVoice = name
            UserDefaults.standard.set(name, forKey: Self.voiceDefaultsKey)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Reloads after the installed model changed (for example after an update).
    func reload() async {
        guard isInstalled else { return }
        await loadModels()
    }

    // MARK: - Private

    private func runDownload(from base: URL) async {
        updateError = nil
        do {
            let manifest = try await ModelManifestSummary.fetch(from: base)
            remote = manifest
            try Self.ensureDiskSpace(for: manifest.totalBytes)
            // Drop the loaded model so the folder can be replaced.
            phonon = nil
            voices = []
            state = .downloading(0)
            let last = Mutex(0.0)
            try await PhononModels.download(from: base) { [weak self] fraction in
                let shouldPublish = last.withLock { previous -> Bool in
                    guard fraction - previous >= 0.005 || fraction >= 1 else { return false }
                    previous = fraction
                    return true
                }
                guard shouldPublish else { return }
                Task { @MainActor in
                    if case .downloading = self?.state { self?.state = .downloading(fraction) }
                }
            }
            updateAvailable = false
            await loadModels()
        } catch is CancellationError {
            await recoverAfterInterruptedDownload(message: nil)
        } catch let error as URLError where error.code == .cancelled {
            await recoverAfterInterruptedDownload(message: nil)
        } catch {
            await recoverAfterInterruptedDownload(message: error.localizedDescription)
        }
    }

    /// An interrupted update keeps the old model usable; a failed first download can be retried
    /// (verified files are kept and not fetched again).
    private func recoverAfterInterruptedDownload(message: String?) async {
        if isInstalled {
            await loadModels()
            updateError = message
        } else if let message {
            state = .failed(message)
        } else {
            state = ModelConfiguration.baseURL == nil ? .notConfigured : .needsDownload
        }
    }

    private func loadModels() async {
        let directory = PhononModels.defaultDirectory
        state = .loading(compiling: Phonon.needsCompiling(directory))
        do {
            let loaded = try await Phonon.load(models: directory, language: .english)
            phonon = loaded
            voices = loaded.voices
            let saved = UserDefaults.standard.string(forKey: Self.voiceDefaultsKey)
            let fallback = voices.contains("default") ? "default" : loaded.voice
            let preferred = saved.flatMap { voices.contains($0) ? $0 : nil } ?? fallback
            if loaded.voice != preferred { try await loaded.setVoice(preferred) }
            selectedVoice = preferred
            state = .ready
        } catch {
            phonon = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// The download plus the compiled copy Core ML keeps beside each model needs roughly twice
    /// the model size; require a little headroom on top.
    private static func ensureDiskSpace(for modelBytes: Int64) throws {
        let needed = Int64(Double(modelBytes) * 2.2)
        let values = try URL.documentsDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < needed {
            let formatter = ByteCountFormatter()
            throw ModelStoreError.notEnoughSpace(
                needed: formatter.string(fromByteCount: needed),
                available: formatter.string(fromByteCount: available)
            )
        }
    }
}

enum ModelStoreError: LocalizedError {
    case notEnoughSpace(needed: String, available: String)

    var errorDescription: String? {
        switch self {
        case let .notEnoughSpace(needed, available):
            "Not enough free space. The model needs about \(needed); \(available) is available."
        }
    }
}
