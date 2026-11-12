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

  /// One glass surface that can morph between a prominent (accent-tinted, button-like) look
  /// and a plain card. Keep the view identity stable and animate `prominent` so the shape and
  /// tint change in place instead of one view replacing another.
  @ViewBuilder
  func morphingSurface(prominent: Bool, cornerRadius: CGFloat = 26) -> some View {
    if #available(iOS 26, *) {
      self.glassEffect(
        prominent ? Glass.regular.tint(.accentColor).interactive() : Glass.regular,
        in: .rect(cornerRadius: cornerRadius)
      )
    } else {
      self.background(
        prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.ultraThinMaterial),
        in: RoundedRectangle(cornerRadius: cornerRadius)
      )
    }
  }

  /// Places `content` centred in the navigation stack's native bottom toolbar. On iOS 26 the
  /// item drops the shared glass capsule so a segmented control keeps its own look.
  @ViewBuilder
  func bottomToolbarItem<Content: View>(@ViewBuilder _ content: @escaping () -> Content)
    -> some View
  {
    if #available(iOS 26, *) {
      self.toolbar {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar, content: content)
          .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible, placement: .bottomBar)
      }
    } else {
      self.toolbar {
        ToolbarItem(placement: .bottomBar, content: content)
      }
    }
  }

  /// Forces the soft (progressive blur) scroll edge effect under bars instead of the hard divider.
  @ViewBuilder
  func softScrollEdgeEffect() -> some View {
    if #available(iOS 26, *) {
      self.scrollEdgeEffectStyle(.soft, for: .all)
    } else {
      self
    }
  }

  /// Removes the scroll edge effect behind the bottom bar only.
  @ViewBuilder
  func hidesBottomScrollEdgeEffect() -> some View {
    if #available(iOS 26, *) {
      self.scrollEdgeEffectHidden(true, for: .bottom)
    } else {
      self
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

/// A large page title that lives in the scroll content: visible at the top, then scrolls away
/// without collapsing into the navigation bar.
struct ScrollingTitle: View {
  let title: String
  /// Leading inset inside a list row: 20 for plain lists, 4 inside an inset-grouped section.
  var leading: CGFloat

  init(_ title: String, leading: CGFloat = 20) {
    self.title = title
    self.leading = leading
  }

  var body: some View {
    Text(title)
      .font(.largeTitle.bold())
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
      .listRowInsets(EdgeInsets(top: 0, leading: leading, bottom: 4, trailing: leading))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
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
