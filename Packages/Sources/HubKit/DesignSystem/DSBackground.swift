import AppKit
import SwiftUI

/// An `NSVisualEffectView` behind the whole window: without a translucent window there
/// is nothing for the materials above it to be translucent over.
struct DSWindowBackdrop: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.state = .active
  }
}

/// Clears the window's opaque background so the backdrop can sample what is behind it.
public struct DSWindowConfigurator: NSViewRepresentable {
  public init() {}

  public func makeNSView(context: Context) -> NSView { ConfiguringView() }
  public func updateNSView(_ nsView: NSView, context: Context) {}

  private final class ConfiguringView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window else { return }
      window.isOpaque = false
      window.backgroundColor = .clear
      window.titlebarAppearsTransparent = true
    }
  }
}

/// Window background: glass backdrop, a soft vertical shade, a teal glow off the top-left corner.
public struct DSBackground: View {
  public init() {}

  public var body: some View {
    ZStack {
      DSWindowBackdrop()
      LinearGradient(
        colors: [Color.white.opacity(0.06), Color.black.opacity(0.24)],
        startPoint: .top, endPoint: .bottom)
      RadialGradient(
        colors: [DS.accent.opacity(0.18), .clear],
        center: UnitPoint(x: 0.10, y: -0.08), startRadius: 0, endRadius: 760
      )
      .blendMode(.plusLighter)
    }
    .ignoresSafeArea()
  }
}
