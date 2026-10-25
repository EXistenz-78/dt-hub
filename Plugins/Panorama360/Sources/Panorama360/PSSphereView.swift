import AppKit
import DTHubDesign
import SwiftUI

/// The view from the centre of the sphere: the rendered picture with the guides, the borders of the stickers and the handles of the selected one over
/// it (the canvas source), or the last result (view only). Drag the empty view to look around, the wheel or a pinch to zoom.
struct PSSphereView: View {
  static let aspect: CGFloat = 4.0 / 3.0
  @ObservedObject var state: PSState
  @State private var pressed = false
  @State private var hovering = false
  @State private var scrollMonitor: Any?
  @State private var lastMagnification = 1.0
  @FocusState private var focused: Bool

  var body: some View {
    GeometryReader { geometry in
      let size = CGSize(width: geometry.size.width, height: geometry.size.width / Self.aspect)
      ZStack {
        Color(red: 0, green: 1, blue: 0)
        if let preview = state.preview {
          Image(decorative: preview, scale: 1).resizable().interpolation(.high).frame(width: size.width, height: size.height)
        }
        Canvas { context, canvasSize in PSSphereOverlay.draw(in: &context, size: canvasSize, state: state) }
        Color.clear.contentShape(Rectangle()).gesture(pointer(size))
          .simultaneousGesture(
            MagnifyGesture()
              .onChanged { value in
                state.sphereZoom(by: -(value.magnification - lastMagnification))
                lastMagnification = value.magnification
              }
              .onEnded { _ in lastMagnification = 1 })
        VStack {
          HStack {
            Text(verbatim: badge).font(.caption.monospaced()).padding(.horizontal, 8).padding(.vertical, 2)
              .background(Capsule().fill(.black.opacity(0.55))).foregroundStyle(.white)
            Spacer(minLength: 0)
          }
          Spacer(minLength: 0)
        }
        .padding(8).allowsHitTesting(false)
      }
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius))
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).stroke(Color.primary.opacity(0.18)))
      .focusable()
      .focusEffectDisabled()
      .focused($focused)
      .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .deleteForward, KeyEquivalent("d")]) { press in
        state.handleKey(press)
      }
      .onContinuousHover { phase in
        if case .active = phase { hovering = true } else { hovering = false }
      }
    }
    .aspectRatio(Self.aspect, contentMode: .fit)
    .onAppear {
      state.refreshPreview(scale: 1)
      guard scrollMonitor == nil else { return }
      scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        // Only the wheel or the trackpad turning over the view, not the momentum of a scroll that began on the page.
        guard hovering, event.momentumPhase.isEmpty else { return event }
        state.sphereZoom(by: -Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04))
        return nil
      }
    }
    .onDisappear {
      if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
      scrollMonitor = nil
    }
    .onChange(of: state.doc.stickers) { refresh() }
    .onChange(of: state.doc.camera) { refresh() }
    .onChange(of: state.doc.source) { refresh() }
    .onChange(of: state.lastResultPath) { refresh() }
    .onChange(of: state.isDragging) { _, dragging in if !dragging { state.refreshPreview(scale: 1) } }
  }

  private func refresh() { state.refreshPreview(scale: state.isDragging ? 0.5 : 1) }

  private var badge: String {
    let c = state.doc.camera
    return String(format: "yaw %.0f° · pitch %.0f° · FOV %.0f°", c.yaw, c.pitch, c.fov)
  }

  private func pointer(_ size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if !pressed {
          pressed = true
          focused = true
          state.spherePointerDown(at: value.location, size: size)
        } else {
          state.spherePointerDragged(to: value.location, size: size, shift: NSEvent.modifierFlags.contains(.shift))
        }
      }
      .onEnded { _ in
        pressed = false
        state.spherePointerUp()
      }
  }
}

/// What is drawn over the sphere view: the horizon, and with the canvas as the source the borders of the stickers and the handles of the selected one.
@MainActor
enum PSSphereOverlay {
  static func draw(in context: inout GraphicsContext, size: CGSize, state: PSState) {
    let camera = state.doc.camera
    if state.doc.guides {
      var horizon = Path()
      var pen = false
      for lon in stride(from: -180.0, through: 180.0, by: 3) {
        let d = Vec3(x: sin(lon * PSProjection.degrees), y: 0, z: cos(lon * PSProjection.degrees))
        if let p = camera.screenPoint(of: d, width: size.width, height: size.height) {
          if pen { horizon.addLine(to: p) } else { horizon.move(to: p) }
          pen = true
        } else {
          pen = false
        }
      }
      context.stroke(horizon, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
    }
    guard state.effectiveSource == .canvas else { return }
    for sticker in state.doc.stickers where sticker.visible {
      let selected = sticker.id == state.doc.selectedID
      var path = Path()
      for line in PSSphere.outline(of: sticker, aspect: state.aspect(of: sticker), camera: camera, size: size) {
        guard let first = line.first else { continue }
        path.move(to: first)
        for p in line.dropFirst() { path.addLine(to: p) }
      }
      context.stroke(path, with: .color(.white.opacity(selected ? 1 : 0.4)), lineWidth: selected ? 2.5 : 1.2)
    }
    guard let selected = state.selected, selected.visible else { return }
    let handles = PSSphere.handles(of: selected, aspect: state.aspect(of: selected), camera: camera, size: size)
    guard let center = handles.center else { return }
    if let rotate = handles.rotate {
      var stem = Path()
      stem.move(to: center)
      stem.addLine(to: rotate)
      context.stroke(stem, with: .color(.white), lineWidth: 1.5)
      let circle = Path(ellipseIn: CGRect(x: rotate.x - 7, y: rotate.y - 7, width: 14, height: 14))
      context.fill(circle, with: .color(DS.accent))
      context.stroke(circle, with: .color(.white), lineWidth: 1.5)
    }
    for case let corner? in handles.corners {
      context.fill(Path(CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10)), with: .color(.white))
    }
    context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(.white))
  }
}
