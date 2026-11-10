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
    /// iOS 26.1+: shows the now-playing bar as the tab view's bottom accessory, so it matches the
    /// tab bar's width and folds inline next to it when the bar minimizes on scroll.
    @ViewBuilder
    func nowPlayingAccessory(playback: PlaybackController, isEnabled: Bool) -> some View {
        if #available(iOS 26.1, *) {
            self
                .tabViewBottomAccessory(isEnabled: isEnabled && playback.currentURL != nil) {
                    NowPlayingAccessory(playback: playback)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Before iOS 26.1: the floating now-playing bar pinned above the tab bar.
    @ViewBuilder
    func legacyNowPlayingInset(playback: PlaybackController) -> some View {
        if #available(iOS 26.1, *) {
            self
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar(playback: playback)
            }
        }
    }
}

/// Content of the tab view bottom accessory. The system supplies the glass capsule.
@available(iOS 26.1, *)
private struct NowPlayingAccessory: View {
    var playback: PlaybackController
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        NowPlayingContent(playback: playback, compact: placement == .inline)
            .padding(.horizontal, placement == .inline ? 12 : 14)
    }
}

/// Compact floating player shown while a file is loaded (iOS 18–26.0). Tap to expand.
struct NowPlayingBar: View {
    var playback: PlaybackController

    var body: some View {
        if playback.currentURL != nil {
            NowPlayingContent(playback: playback, compact: false)
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .controlSurface(cornerRadius: 22)
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
    @State private var showPlayer = false

    var body: some View {
        if let url = playback.currentURL {
            HStack(spacing: compact ? 8 : 12) {
                Button {
                    showPlayer = true
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
            .sheet(isPresented: $showPlayer) {
                PlayerSheet(playback: playback)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var progress: CGFloat {
        playback.duration > 0 ? CGFloat(playback.position / playback.duration) : 0
    }
}

/// Full player: scrubber, skip, play/pause and speed.
struct PlayerSheet: View {
    var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text(displayTitle(playback.currentTitle))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("Phonon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }),
                    in: 0...max(playback.duration, 1)
                )
                .accessibilityLabel("Position")
                HStack {
                    Text(clockText(playback.position))
                    Spacer()
                    Text("-" + clockText(playback.duration - playback.position))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 44) {
                Button { playback.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15").font(.title)
                }
                .accessibilityLabel("Back 15 seconds")

                Button {
                    if let url = playback.currentURL { playback.toggle(url) }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                Button { playback.skip(by: 30) } label: {
                    Image(systemName: "goforward.30").font(.title)
                }
                .accessibilityLabel("Forward 30 seconds")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            SpeedMenu(playback: playback) {
                Label("Speed \(rateLabel(playback.rate))", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.fill.tertiary, in: .capsule)
            }
            .foregroundStyle(.primary)

            if let message = playback.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
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
