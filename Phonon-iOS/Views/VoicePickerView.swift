import SwiftUI

/// Browse, preview and choose a voice. Grouped by accent, filterable by gender.
struct VoicePickerView: View {
    var store: ModelStore
    var previewer: VoicePreviewer
    var isLocked: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", female = "Female", male = "Male", character = "Characters"
        var id: Self { self }
    }

    private var voices: [VoiceInfo] {
        store.voices.map(VoiceCatalog.info(for:)).filter { voice in
            switch filter {
            case .all: true
            case .female: voice.gender == .female
            case .male: voice.gender == .male
            case .character: voice.gender == .character
            }
        }
    }

    /// Accent groups in a stable order, with unknowns last.
    private var sections: [(accent: String, voices: [VoiceInfo])] {
        let order = ["Default", "American", "British", "Character", "Other"]
        let grouped = Dictionary(grouping: voices, by: \.accent)
        return grouped.keys
            .sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
            .map { accent in
                (accent, grouped[accent, default: []].sorted { $0.displayName < $1.displayName })
            }
    }

    var body: some View {
        List {
            if store.voices.isEmpty {
                ContentUnavailableView(
                    "Voices Unavailable",
                    systemImage: "person.wave.2",
                    description: Text("Voices appear once the voice model is downloaded.")
                )
                .listRowBackground(Color.clear)
            } else if voices.isEmpty {
                ContentUnavailableView("No \(filter.rawValue) Voices", systemImage: "person.wave.2")
                    .listRowBackground(Color.clear)
            }
            ForEach(sections, id: \.accent) { section in
                Section(sectionTitle(section.accent)) {
                    ForEach(section.voices) { voice in
                        VoiceRow(
                            voice: voice,
                            isSelected: store.selectedVoice == voice.id,
                            isPreviewing: previewer.isPlaying && previewer.playingVoice == voice.id,
                            select: { select(voice) },
                            preview: { previewer.toggle(voice: voice.id, store: store) }
                        )
                        .disabled(isLocked)
                    }
                }
            }
            if let message = previewer.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .topBar {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onDisappear { previewer.stop() }
    }

    private func sectionTitle(_ accent: String) -> String {
        switch accent {
        case "American", "British": "\(accent) English"
        case "Character": "Characters"
        default: accent
        }
    }

    private func select(_ voice: VoiceInfo) {
        Task { await store.selectVoice(voice.id) }
    }
}

private struct VoiceRow: View {
    let voice: VoiceInfo
    let isSelected: Bool
    let isPreviewing: Bool
    var select: () -> Void
    var preview: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: select) {
                HStack(spacing: 14) {
                    VoiceAvatar(voice: voice, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.displayName)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        if let gender = voice.gender, gender != .character {
                            Text("\(gender.title) · \(voice.accent)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: preview) {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.footnote.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(.tint.opacity(0.12), in: .circle)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel(isPreviewing ? "Stop preview" : "Preview \(voice.displayName)")
        }
        .padding(.vertical, 2)
    }
}

/// Initials in a tinted circle; the hue is derived from the name so each voice keeps its colour.
struct VoiceAvatar: View {
    let voice: VoiceInfo
    var size: CGFloat = 40

    private var hue: Double {
        let sum = voice.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(sum % 360) / 360
    }

    var body: some View {
        Text(voice.initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.55, brightness: 0.85),
                        Color(hue: hue, saturation: 0.7, brightness: 0.6),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .circle
            )
            .accessibilityHidden(true)
    }
}
