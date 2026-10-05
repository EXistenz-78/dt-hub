import SwiftUI

/// .ultraThinMaterial @ 19 · stroke .thinMaterial 1pt @ 18, brightness +0.1 ·
/// shadow black 20%, radius 2, y 4. Padding is left to the caller.
/// The shadow belongs to the panel's shape only: on the whole view it would also fall under
/// every text inside, blurring it.
struct DSPanel: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: DS.panelRadius, style: .continuous)
          .fill(.ultraThinMaterial)
          .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 4)
      }
      .overlay(
        RoundedRectangle(cornerRadius: DS.panelStrokeRadius, style: .continuous)
          .strokeBorder(.thinMaterial, lineWidth: 1)
          .brightness(0.1)
      )
  }
}

extension View {
  public func dsPanel() -> some View { modifier(DSPanel()) }
}

/// Panel header bar: overlaps the top of the panel, rounded 19 on top, square at the
/// bottom, one shade darker than the panel.
public struct DSPanelHeader: View {
  let icon: String
  let title: String

  public init(icon: String, title: String) {
    self.icon = icon
    self.title = title
  }

  public var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 10)
    .padding(.bottom, 12)
    .background {
      UnevenRoundedRectangle(
        topLeadingRadius: DS.panelRadius, bottomLeadingRadius: 0,
        bottomTrailingRadius: 0, topTrailingRadius: DS.panelRadius, style: .continuous
      )
      .fill(.ultraThinMaterial)
      .brightness(-0.02)
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
    }
  }
}

/// Structural group label: mono, uppercase, tracked, secondary.
public struct DSGroupHeader: View {
  let title: String
  let prominent: Bool

  public init(title: String, prominent: Bool = false) {
    self.title = title
    self.prominent = prominent
  }

  public var body: some View {
    Text(title.uppercased())
      .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
      .tracking(0.8)
      .foregroundStyle(prominent ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary))
  }
}
