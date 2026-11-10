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

    /// Pins `content` under the navigation bar. On iOS 26 it joins the bar's scroll edge effect
    /// (progressive blur); earlier versions fall back to a bar material.
    @ViewBuilder
    func topBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) { content().background(.bar) }
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
