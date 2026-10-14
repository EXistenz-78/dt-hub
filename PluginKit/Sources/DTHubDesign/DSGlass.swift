import SwiftUI

/// Liquid Glass in the given shape on macOS 26; on macOS 15, which has no Liquid Glass, a material in the same shape
/// (`DSGlassFallback`).
struct DSGlass<S: Shape>: ViewModifier {
  let shape: S
  let tint: Color?
  let interactive: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.glassEffect(glass, in: shape)
    } else {
      content.modifier(DSGlassFallback(shape: shape, tint: tint))
    }
  }

  @available(macOS 26, *)
  private var glass: Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    return glass.interactive(interactive)
  }
}

/// What stands in for the glass on macOS 15: a thin material in the shape, with the tint under it so a prominent button
/// keeps its colour, and a faint edge. `interactive` has no counterpart.
struct DSGlassFallback<S: Shape>: ViewModifier {
  let shape: S
  let tint: Color?

  func body(content: Content) -> some View {
    content
      .background {
        ZStack {
          if let tint { shape.fill(tint) }
          shape.fill(.ultraThinMaterial)
        }
      }
      .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
  }
}

extension View {
  public func dsGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
    modifier(DSGlass(shape: shape, tint: tint, interactive: interactive))
  }
}
