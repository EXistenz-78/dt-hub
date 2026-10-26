import AppKit
import Combine
import SwiftUI

/// Shows the picture of a `PSPreview` on a layer and puts every new image there as soon as it is made, without going through SwiftUI's diffing of an
/// `Image`: the picture of the canvas and of the sphere view is replaced many times a second.
final class PSLayerHostView: NSView {
  private var subscription: AnyCancellable?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.contentsGravity = .resize
    layer?.magnificationFilter = .linear
    layer?.minificationFilter = .linear
    layer?.drawsAsynchronously = false
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  /// Follows this box (and no other).
  @MainActor
  func bind(_ box: PSPreview) {
    subscription = box.$image.sink { [weak self] image in
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      self?.layer?.contents = image
      CATransaction.commit()
    }
  }

  /// The pointer belongs to the gestures over it, not to this view.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct PSImageLayerView: NSViewRepresentable {
  let previewBox: PSPreview

  func makeNSView(context: Context) -> PSLayerHostView {
    let view = PSLayerHostView()
    view.bind(previewBox)
    return view
  }

  func updateNSView(_ view: PSLayerHostView, context: Context) {}
}
