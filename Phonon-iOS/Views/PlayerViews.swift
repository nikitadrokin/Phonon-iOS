import SwiftUI

/// "1×", "1.25×", "2.5×".
func rateLabel(_ rate: Float) -> String {
    rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
}

func clockText(_ seconds: Double) -> String {
    let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
    return Duration.seconds(max(seconds, 0)).formatted(.time(pattern: pattern))
}

/// Menu of playback speeds, 0.5× to 2.5×.
struct SpeedMenu<Label: View>: View {
    var playback: PlaybackController
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            Picker("Playback Speed", selection: Binding(
                get: { playback.rate },
                set: { playback.setRate($0) }
            )) {
                ForEach(PlaybackController.rates.reversed(), id: \.self) { rate in
                    Text(rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            label()
        }
        .accessibilityLabel("Playback speed, \(rateLabel(playback.rate))")
    }
}

extension View {
    /// iOS 26+: the now-playing bar as the tab view's bottom accessory, on every tab. It stays
    /// mounted even when nothing is loaded, because the tab bar only stretches to full width while
    /// an accessory is attached; toggling it would make the bar jump between widths.
    @ViewBuilder
    func nowPlayingAccessory(playback: PlaybackController, library: ExportLibrary) -> some View {
        if #available(iOS 26, *) {
            self
                .tabViewBottomAccessory {
                    NowPlayingAccessory(playback: playback, library: library)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Before iOS 26: the floating now-playing bar pinned above the tab bar.
    @ViewBuilder
    func legacyNowPlayingInset(playback: PlaybackController) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar(playback: playback)
            }
        }
    }
}

/// Content of the tab view bottom accessory. The system supplies the glass capsule.
@available(iOS 26, *)
private struct NowPlayingAccessory: View {
    var playback: PlaybackController
    var library: ExportLibrary
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.nowPlayingNamespace) private var namespace

    var body: some View {
        let compact = placement == .inline
        Group {
            if playback.currentURL != nil {
                NowPlayingContent(playback: playback, compact: compact)
            } else {
                IdleAccessoryContent(latest: library.items.first, playback: playback, compact: compact)
            }
        }
        .padding(.horizontal, compact ? 12 : 14)
        .nowPlayingTransitionSource(namespace)
    }
}

/// Accessory while nothing is loaded: offers the newest export, or says nothing is playing.
@available(iOS 26, *)
private struct IdleAccessoryContent: View {
    let latest: ExportItem?
    var playback: PlaybackController
    var compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)
                .background(.fill.tertiary, in: .rect(cornerRadius: compact ? 8 : 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(latest.map { displayTitle($0.name) } ?? "Not Playing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(latest == nil ? .secondary : .primary)
                    .lineLimit(1)
                if !compact, let latest {
                    Text("Latest · \(clockText(latest.duration))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                if let latest { playback.toggle(latest.url) }
            } label: {
                Image(systemName: "play.fill")
                    .font(compact ? .body : .title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(latest == nil)
            .accessibilityLabel(latest.map { "Play \(displayTitle($0.name))" } ?? "Nothing to play")
        }
    }
}

/// Compact floating player shown while a file is loaded (iOS 18–26.0). Tap to expand.
struct NowPlayingBar: View {
    var playback: PlaybackController
    @Environment(\.nowPlayingNamespace) private var namespace

    var body: some View {
        if playback.currentURL != nil {
            NowPlayingContent(playback: playback, compact: false)
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .controlSurface(cornerRadius: 22)
                .nowPlayingTransitionSource(namespace)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Artwork, title, speed and play/pause. `compact` drops the time line and speed menu so the row
/// fits beside a minimized tab bar.
private struct NowPlayingContent: View {
    var playback: PlaybackController
    var compact: Bool
    @Environment(\.expandNowPlaying) private var expand

    var body: some View {
        if let url = playback.currentURL {
            HStack(spacing: compact ? 8 : 12) {
                Button {
                    expand?()
                } label: {
                    HStack(spacing: compact ? 8 : 12) {
                        Image(systemName: "waveform")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .symbolEffect(.variableColor.iterative, isActive: playback.isPlaying)
                            .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)
                            .background(.tint.opacity(0.14), in: .rect(cornerRadius: compact ? 8 : 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayTitle(playback.currentTitle))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if !compact {
                                Text("\(clockText(playback.position)) / \(clockText(playback.duration))")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if !compact {
                    SpeedMenu(playback: playback) {
                        Text(rateLabel(playback.rate))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .frame(minWidth: 44, minHeight: 32)
                    }
                }

                Button {
                    playback.toggle(url)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(compact ? .body : .title3)
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            }
            .overlay(alignment: .bottom) {
                if !compact {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.tint)
                            .frame(width: proxy.size.width * progress, height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 8)
                    .offset(y: 6)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var progress: CGFloat {
        playback.duration > 0 ? CGFloat(playback.position / playback.duration) : 0
    }
}

extension EnvironmentValues {
    /// Opens the full-screen player. Set by `ContentView`, which owns the presentation.
    @Entry var expandNowPlaying: (@MainActor () -> Void)? = nil
    /// Namespace the mini player and the full-screen player zoom between.
    @Entry var nowPlayingNamespace: Namespace.ID? = nil
}

enum NowPlayingTransition {
    static let id = "now-playing"
}

extension View {
    /// Marks this view as the source the full-screen player zooms out of and back into.
    @ViewBuilder
    func nowPlayingTransitionSource(_ namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedTransitionSource(id: NowPlayingTransition.id, in: namespace)
        } else {
            self
        }
    }
}

/// Turns `Some-Essay-Title-20261109-101500` into `Some Essay Title`.
func displayTitle(_ fileName: String?) -> String {
    guard let fileName else { return "" }
    var parts = fileName.split(separator: "-").map(String.init)
    if parts.count > 2, parts[parts.count - 1].count == 6, parts[parts.count - 2].count == 8,
       parts.suffix(2).allSatisfy({ $0.allSatisfy(\.isNumber) }) {
        parts.removeLast(2)
    }
    let title = parts.joined(separator: " ")
    return title.isEmpty ? fileName : title
}
