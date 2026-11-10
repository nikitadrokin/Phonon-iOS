import SwiftUI

/// Liquid Glass on iOS 26+, with a plain material fallback on iOS 18-25.
extension View {
    /// Glass surface behind floating controls. Do not use on content.
    @ViewBuilder
    func controlSurface(cornerRadius: CGFloat = 24) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// A glass control floating at the bottom, sized and placed where the (hidden) tab bar sits.
    @ViewBuilder
    func bottomFilterBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: .bottom) {
                content()
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular.interactive())
                    // Padding and offset match the tab bar's footprint.
                    .padding(.horizontal, 26)
                    .offset(y: 4)
            }
        } else {
            self.safeAreaInset(edge: .bottom) {
                content()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }

    /// Navigation subtitle on iOS 26; nothing earlier.
    @ViewBuilder
    func subtitle(_ text: String?) -> some View {
        if #available(iOS 26, *) {
            self.navigationSubtitle(text ?? "")
        } else {
            self
        }
    }

    /// Glass button style, or the closest bordered style before iOS 26.
    @ViewBuilder
    func adaptiveButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

/// Groups glass controls so they render and blend together on iOS 26+.
struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
