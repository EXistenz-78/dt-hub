import SwiftUI

/// The frame of the workspace tabs: one glass panel under the header, as tall as the window
/// leaves it, with a bar for the tab titles on top and the active tab's content inside. It is
/// part of the window, not of any tab, so every tab (plug-ins included) sits in the same frame.
public struct DSTabFrame<Bar: View, Content: View>: View {
  let bar: Bar
  let content: Content

  public init(@ViewBuilder bar: () -> Bar, @ViewBuilder content: () -> Content) {
    self.bar = bar()
    self.content = content()
  }

  public var body: some View {
    VStack(spacing: 0) {
      bar
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          UnevenRoundedRectangle(
            topLeadingRadius: DS.panelRadius, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: DS.panelRadius, style: .continuous
          )
          .fill(Color.black.opacity(0.14))
        }
        .overlay(alignment: .bottom) {
          Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
      // Only the content is clipped (its bottom corners follow the panel): Liquid Glass in the
      // bar does not draw its tint inside a clipped ancestor.
      content
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
          UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: DS.panelRadius,
            bottomTrailingRadius: DS.panelRadius, topTrailingRadius: 0, style: .continuous))
    }
    // A light teal wash over the translucent material: the backdrop still shows through.
    .background(
      RoundedRectangle(cornerRadius: DS.panelRadius, style: .continuous).fill(DS.accent.opacity(0.15))
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .dsPanel()
  }
}
