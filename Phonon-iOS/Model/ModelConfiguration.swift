import Foundation

/// The voice model the app installs and where it comes from.
///
/// The app uses Phonon 31m English (`gradium/phonon-31m-en`). The Swift runtime loads Core ML
/// bundles, not the GGUF/safetensors weights on Hugging Face, so the download source is a Core ML
/// export of that model (see `scripts/publish-model.sh`). The folder served at the base URL must
/// contain `bundle.json` and every file it lists. The base URL is the `PHONON_MODEL_BASE_URL`
/// build setting; there is deliberately no runtime override.
nonisolated enum ModelConfiguration {
  /// Name shown in the UI.
  static let displayName = "Phonon 31m (English)"

  /// The upstream Hugging Face repository the bundle is exported from.
  static let upstreamRepositoryID = "gradium/phonon-31m-en"

  /// The upstream model page, for attribution and license terms.
  static let upstreamPageURL = URL(string: "https://huggingface.co/gradium/phonon-31m-en")

  /// The upstream license. It does not allow commercial use.
  static let licenseName = "CC BY-NC 4.0"

  /// The build-time download source, empty when the build setting is unset.
  static var buildSettingURLString: String {
    let value = Bundle.main.object(forInfoDictionaryKey: "PhononModelBaseURL") as? String
    return (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// A validated base URL, or nil when nothing usable is configured. Release builds require
  /// HTTPS; debug builds also accept HTTP for local testing.
  static var baseURL: URL? { validatedURL(from: buildSettingURLString) }

  /// The source in a short readable form (for example `huggingface.co/user/repo`).
  static var sourceDescription: String? {
    guard let url = baseURL, let host = url.host() else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    let path = parts.prefix { $0 != "resolve" }.joined(separator: "/")
    return path.isEmpty ? host : "\(host)/\(path)"
  }

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
    guard let data = try? Data(contentsOf: directory.appending(path: "bundle.json")) else {
      return nil
    }
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
