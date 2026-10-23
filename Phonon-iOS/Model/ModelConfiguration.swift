import Foundation

/// Where the Core ML model folder is hosted.
///
/// The folder served at this URL must contain `bundle.json` and every file it lists (the contents
/// of `phonon-31m-en-coreml.zip` from the xn-ptts GitHub release). The default comes from the
/// `PHONON_MODEL_BASE_URL` build setting; Settings can override it at runtime.
nonisolated enum ModelConfiguration {
    /// UserDefaults key for the runtime override.
    static let overrideDefaultsKey = "modelBaseURLOverride"

    /// The build-time default, empty when the build setting is unset.
    static var buildSettingURLString: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "PhononModelBaseURL") as? String
        return (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The runtime override, empty when unset.
    static var overrideURLString: String {
        (UserDefaults.standard.string(forKey: overrideDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The URL in effect: the override when set, otherwise the build setting.
    static var effectiveURLString: String {
        overrideURLString.isEmpty ? buildSettingURLString : overrideURLString
    }

    /// A validated base URL, or nil when nothing usable is configured. Release builds require
    /// HTTPS; debug builds also accept HTTP for local testing.
    static var baseURL: URL? { validatedURL(from: effectiveURLString) }

    static func validatedURL(from string: String) -> URL? {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              let host = url.host(), !host.isEmpty
        else { return nil }
        #if DEBUG
        return (scheme == "https" || scheme == "http") ? url : nil
        #else
        return scheme == "https" ? url : nil
        #endif
    }
}

/// The parts of the hosted `bundle.json` the app needs, read independently of the package.
nonisolated struct ModelManifestSummary: Decodable, Sendable, Equatable {
    struct File: Decodable, Sendable, Equatable {
        let size: Int
    }

    /// Export timestamp; changes whenever the hosted model changes.
    let built: Int
    let files: [File]

    var totalBytes: Int64 { files.reduce(0) { $0 + Int64($1.size) } }

    /// Reads the manifest from the installed model folder.
    static func installed(at directory: URL) -> ModelManifestSummary? {
        guard let data = try? Data(contentsOf: directory.appending(path: "bundle.json")) else { return nil }
        return try? JSONDecoder().decode(ModelManifestSummary.self, from: data)
    }

    /// Fetches the manifest from the host.
    static func fetch(from base: URL) async throws -> ModelManifestSummary {
        var request = URLRequest(url: base.appending(path: "bundle.json"))
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ModelManifestSummary.self, from: data)
    }
}
