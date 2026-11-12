import AVKit
import SwiftUI

/// Full-screen now-playing view in the style of Apple Music: artwork, scrubber, transport and a
/// transcript page that follows the audio paragraph by paragraph. Swipe down to close.
struct FullPlayerView: View {
    var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var transcript: Transcript?
    @State private var showsTranscript = false
    @State private var isEditing = false
    @Namespace private var artworkSpace

    private let layoutSpring = Animation.spring(duration: 0.45, bounce: 0.15)

    var body: some View {
        VStack(spacing: 0) {
            grabber

            if showsTranscript, let transcript {
                compactHeader
                    .padding(.top, 12)
                TranscriptPage(transcript: transcript, playback: playback)
                    .transition(.opacity)
            } else {
                PlayerArtwork(isPlaying: playback.isPlaying, cornerRadius: 14, symbolSize: 88)
                    .matchedGeometryEffect(id: "artwork", in: artworkSpace)
                    .aspectRatio(1, contentMode: .fit)
                    .scaleEffect(playback.isPlaying ? 1 : 0.82)
                    .shadow(color: .black.opacity(playback.isPlaying ? 0.35 : 0.2), radius: 28, y: 14)
                    .animation(.spring(duration: 0.55, bounce: 0.3), value: playback.isPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 28)
                titleRow
            }

            PlayerScrubber(playback: playback)
                .padding(.top, 20)
            transport
            bottomBar
        }
        .padding(.horizontal, 28)
        .foregroundStyle(.white)
        .background { PlayerBackground(isPlaying: playback.isPlaying) }
        .environment(\.colorScheme, .dark)
        .task(id: playback.currentURL) {
            transcript = playback.currentURL.flatMap(TranscriptStore.load(for:))
            if transcript == nil { showsTranscript = false }
        }
        .onChange(of: playback.currentURL) { _, url in
            if url == nil { dismiss() }
        }
        .sheet(isPresented: $isEditing) {
            if let transcript {
                TranscriptEditor(transcript: transcript) { save($0) }
            }
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: - Pieces

    private var grabber: some View {
        Button {
            dismiss()
        } label: {
            Capsule()
                .fill(.white.opacity(0.4))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close player")
        .padding(.top, 6)
    }

    private var title: String { displayTitle(playback.currentTitle) }

    private var subtitle: String {
        let format = playback.currentURL?.pathExtension.uppercased() ?? ""
        return format.isEmpty ? "Phonon" : "Phonon · \(format)"
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            moreMenu
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 14) {
            PlayerArtwork(isPlaying: playback.isPlaying, cornerRadius: 8, symbolSize: 24)
                .matchedGeometryEffect(id: "artwork", in: artworkSpace)
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            if let url = playback.currentURL {
                ShareLink(item: url)
            }
            if transcript != nil {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit Transcript", systemImage: "pencil")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.15), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("More")
    }

    private var transport: some View {
        HStack {
            Spacer()
            Button { playback.skip(by: -15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 30, weight: .medium))
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel("Back 15 seconds")
            Spacer()
            Button {
                if let url = playback.currentURL { playback.toggle(url) }
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
                    .frame(width: 80, height: 80)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { playback.skip(by: 30) } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 30, weight: .medium))
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel("Forward 30 seconds")
            Spacer()
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }

    private var bottomBar: some View {
        HStack {
            SpeedMenu(playback: playback) {
                Text(rateLabel(playback.rate))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 44, minHeight: 44)
            }

            Spacer()

            Button {
                withAnimation(layoutSpring) { showsTranscript.toggle() }
            } label: {
                Image(systemName: showsTranscript ? "quote.bubble.fill" : "quote.bubble")
                    .font(.title3)
                    .foregroundStyle(showsTranscript ? Color.black : Color.white.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .background(showsTranscript ? Color.white.opacity(0.85) : .clear, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(transcript == nil)
            .opacity(transcript == nil ? 0.35 : 1)
            .accessibilityLabel(showsTranscript ? "Hide transcript" : "Show transcript")

            Spacer()

            AirPlayButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.bottom, 8)
    }

    private func save(_ edited: Transcript) {
        guard let url = playback.currentURL else { return }
        try? TranscriptStore.save(edited, for: url)
        transcript = edited
    }
}

// MARK: - Artwork

/// Stand-in artwork: a tinted tile with a waveform that moves while audio plays.
private struct PlayerArtwork: View {
    var isPlaying: Bool
    var cornerRadius: CGFloat
    var symbolSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(
                colors: [Color.accentColor, Color.accentColor.mix(with: .black, by: 0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Scrubber

/// Thin capsule that thickens while dragged. Dragging is relative, so grabbing it never jumps.
private struct PlayerScrubber: View {
    var playback: PlaybackController
    @State private var dragValue: Double?
    @State private var dragOrigin: Double = 0

    var body: some View {
        let duration = max(playback.duration, 0.01)
        let value = min(max(dragValue ?? playback.position, 0), duration)
        let isDragging = dragValue != nil

        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(.white.opacity(isDragging ? 1 : 0.7))
                        .frame(width: width * value / duration)
                }
                .frame(height: isDragging ? 14 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if dragValue == nil { dragOrigin = playback.position }
                            let delta = gesture.translation.width / width * duration
                            dragValue = min(max(dragOrigin + delta, 0), duration)
                        }
                        .onEnded { _ in
                            if let dragValue { playback.seek(to: dragValue) }
                            dragValue = nil
                        }
                )
            }
            .frame(height: 28)
            .scaleEffect(x: isDragging ? 1.03 : 1)

            HStack {
                Text(clockText(value))
                Spacer()
                Text("-" + clockText(duration - value))
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(isDragging ? 0.9 : 0.55))
        }
        .animation(.spring(duration: 0.3), value: isDragging)
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }),
                in: 0...duration
            ) {
                Text("Position")
            }
        }
    }
}

// MARK: - Transcript

/// Lyrics-style transcript. The paragraph being spoken is bright and kept in view; tap any
/// paragraph to play from it. Scrolling by hand pauses the follow for a few seconds.
private struct TranscriptPage: View {
    let transcript: Transcript
    var playback: PlaybackController
    @State private var isUserScrolling = false
    @State private var resumeFollow: Task<Void, Never>?

    private var current: Int? { transcript.segmentIndex(at: playback.position) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !transcript.isTimed {
                        Text("This transcript isn't synced to the audio.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(Array(transcript.segments.enumerated()), id: \.element.id) { index, segment in
                        row(segment, isCurrent: index == current)
                            .id(segment.id)
                    }
                }
                .padding(.vertical, 36)
            }
            .scrollIndicators(.hidden)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    resumeFollow?.cancel()
                    isUserScrolling = true
                } else if phase == .idle, isUserScrolling {
                    resumeFollow = Task {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        isUserScrolling = false
                    }
                }
            }
            .onAppear { follow(proxy, animated: false) }
            .onChange(of: current) { follow(proxy, animated: true) }
            .onChange(of: isUserScrolling) { _, scrolling in
                if !scrolling { follow(proxy, animated: true) }
            }
        }
    }

    private func row(_ segment: Transcript.Segment, isCurrent: Bool) -> some View {
        let timed = transcript.isTimed
        return Text(segment.text)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white.opacity(!timed ? 0.9 : isCurrent ? 1 : 0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture {
                guard let start = segment.start, let url = playback.currentURL else { return }
                playback.seek(to: start)
                if !playback.isPlaying { playback.toggle(url) }
                isUserScrolling = false
            }
            .animation(.easeInOut(duration: 0.35), value: isCurrent)
            .accessibilityAddTraits(timed ? .isButton : [])
            .accessibilityHint(timed ? "Plays from this paragraph" : "")
    }

    private func follow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !isUserScrolling, let current else { return }
        let id = transcript.segments[current].id
        if animated {
            withAnimation(.spring(duration: 0.6, bounce: 0.1)) {
                proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.2))
            }
        } else {
            proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.2))
        }
    }
}

/// Plain-text editor for a transcript. Paragraphs are separated by blank lines; keeping the
/// same number of paragraphs keeps the transcript synced to the audio.
private struct TranscriptEditor: View {
    let transcript: Transcript
    var onSave: (Transcript) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(transcript: Transcript, onSave: @escaping (Transcript) -> Void) {
        self.transcript = transcript
        self.onSave = onSave
        _text = State(initialValue: transcript.text)
    }

    private var edited: Transcript { transcript.edited(text) }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .padding(.horizontal, 12)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if transcript.isTimed {
                        Text(edited.isTimed
                             ? "Keep a blank line between paragraphs to stay synced with the audio."
                             : "The number of paragraphs changed, so the transcript will no longer follow the audio.")
                            .font(.footnote)
                            .foregroundStyle(edited.isTimed ? Color.secondary : Color.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.bar)
                    }
                }
                .navigationTitle("Edit Transcript")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(edited)
                            dismiss()
                        }
                        .disabled(edited.segments.isEmpty)
                    }
                }
        }
    }
}

// MARK: - Background and AirPlay

/// Slowly drifting mesh gradient in the app tint, frozen while paused or with Reduce Motion.
private struct PlayerBackground: View {
    var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || reduceMotion)) { context in
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: context.date.timeIntervalSinceReferenceDate),
                colors: colors
            )
        }
        .overlay(Color.black.opacity(0.2))
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        let tint = Color.accentColor
        return [
            tint.mix(with: .black, by: 0.45), tint.mix(with: .indigo, by: 0.5).mix(with: .black, by: 0.4), tint.mix(with: .black, by: 0.65),
            tint.mix(with: .purple, by: 0.35).mix(with: .black, by: 0.5), tint.mix(with: .black, by: 0.3), tint.mix(with: .black, by: 0.6),
            tint.mix(with: .black, by: 0.75), tint.mix(with: .indigo, by: 0.4).mix(with: .black, by: 0.55), tint.mix(with: .black, by: 0.5)
        ]
    }

    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(time * 0.35)) * 0.14
        let b = Float(cos(time * 0.27)) * 0.14
        return [
            [0, 0], [0.5 + b * 0.5, 0], [1, 0],
            [0, 0.5 + b], [0.5 + a, 0.5 - b], [1, 0.5 - a],
            [0, 1], [0.5 - a * 0.5, 1], [1, 1]
        ]
    }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.75)
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
