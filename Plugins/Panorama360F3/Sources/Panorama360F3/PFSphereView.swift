import AppKit
import DTHubDesign
import SwiftUI

/// The view from the centre of the sphere: the shown panorama, 4:3. Drag to look around, the wheel or a pinch to zoom, the button looks straight ahead.
/// Adapted from Panorama 360's `PSSphereView` (only the result is shown: no stickers, no handles).
struct PFSphereView: View {
  static let aspect: CGFloat = 4.0 / 3.0
  /// The picture is drawn at this size and scaled to the view.
  static let renderSize = (width: 1024, height: 768)
  @ObservedObject var state: PFState

  @State private var lastTranslation = CGSize.zero
  @State private var lastMagnification = 1.0
  @State private var hovering = false
  @State private var scrollMonitor: Any?

  var body: some View {
    GeometryReader { geometry in
      let size = CGSize(width: geometry.size.width, height: geometry.size.width / Self.aspect)
      ZStack(alignment: .topTrailing) {
        Color.black.opacity(0.85)
        if let image = state.preview {
          Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
        } else {
          Text(state.text(.noResultYet)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        Button { state.resetCamera() } label: { Image(systemName: "scope") }
          .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.resetView)).padding(8)
      }
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius))
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).stroke(Color.primary.opacity(0.18)))
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            state.lookAround(
              dx: Double(value.translation.width - lastTranslation.width), dy: Double(value.translation.height - lastTranslation.height),
              width: Double(size.width))
            lastTranslation = value.translation
          }
          .onEnded { _ in lastTranslation = .zero }
      )
      .simultaneousGesture(
        MagnifyGesture()
          .onChanged { value in
            state.zoom(by: -(value.magnification - lastMagnification))
            lastMagnification = value.magnification
          }
          .onEnded { _ in lastMagnification = 1 }
      )
      .onHover { hovering = $0 }
    }
    .aspectRatio(Self.aspect, contentMode: .fit)
    .onAppear {
      render()
      guard scrollMonitor == nil else { return }
      scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        // Only the wheel or the trackpad turning over the view, not the momentum of a scroll that began on the page.
        guard hovering, event.momentumPhase.isEmpty else { return event }
        state.zoom(by: -Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04))
        return nil
      }
    }
    .onDisappear {
      if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
      scrollMonitor = nil
    }
    .onChange(of: state.camera) { render() }
    .onChange(of: state.lastResultPath) { render() }
  }

  private func render() {
    Task { await state.renderPreview(width: Self.renderSize.width, height: Self.renderSize.height) }
  }
}
