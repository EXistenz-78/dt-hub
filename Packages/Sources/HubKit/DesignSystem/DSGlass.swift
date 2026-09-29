import SwiftUI

/// Liquid Glass in the given shape. DT Hub requires macOS 26, so there is no material fallback.
struct DSGlass<S: Shape>: ViewModifier {
  let shape: S
  let tint: Color?
  let interactive: Bool

  func body(content: Content) -> some View {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    return content.glassEffect(glass.interactive(interactive), in: shape)
  }
}

extension View {
  public func dsGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
    modifier(DSGlass(shape: shape, tint: tint, interactive: interactive))
  }
}
