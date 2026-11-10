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

/// Compact floating player shown while a file is loaded. Tap to expand.
struct NowPlayingBar: View {
    var playback: PlaybackController
    @State private var showPlayer = false

    var body: some View {
        if let url = playback.currentURL {
            HStack(spacing: 12) {
                Button {
                    showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .symbolEffect(.variableColor.iterative, isActive: playback.isPlaying)
                            .frame(width: 36, height: 36)
                            .background(.tint.opacity(0.14), in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayTitle(playback.currentTitle))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(clockText(playback.position)) / \(clockText(playback.duration))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                SpeedMenu(playback: playback) {
                    Text(rateLabel(playback.rate))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 44, minHeight: 32)
                }

                Button {
                    playback.toggle(url)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.tint)
                        .frame(width: proxy.size.width * progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 18)
                .allowsHitTesting(false)
            }
            .controlSurface(cornerRadius: 22)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .sheet(isPresented: $showPlayer) {
                PlayerSheet(playback: playback)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
