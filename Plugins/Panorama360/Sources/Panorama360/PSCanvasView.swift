import AppKit
import DTHubDesign
import SwiftUI

/// The ERP: the rendered panorama with the guides, the borders of the stickers and the handles of the selected one over it.
struct PSCanvasView: View {
  @ObservedObject var state: PSState
  @State private var pressed = false
  @FocusState private var focused: Bool
  @State private var dropTargeted = false

  var body: some View {
    GeometryReader { geometry in
      let size = CGSize(width: geometry.size.width, height: geometry.size.width / 2)
      ZStack {
        Color(red: 0, green: 1, blue: 0)
        if let preview = state.preview {
          Image(decorative: preview, scale: 1).resizable().interpolation(.high).frame(width: size.width, height: size.height)
        }
        Canvas { context, canvasSize in PSOverlay.draw(in: &context, size: canvasSize, state: state) }
        Color.clear.contentShape(Rectangle()).gesture(pointer(size))
      }
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius))
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).stroke(Color.primary.opacity(0.18)))
      .overlay {
        if dropTargeted {
          ZStack {
            RoundedRectangle(cornerRadius: DS.boxRadius).fill(DS.accent.opacity(0.25))
            RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            Text(state.text(.dropHere)).font(.headline)
          }
        }
      }
      .onDrop(of: PSDrop.types, isTargeted: $dropTargeted) { providers in
        let temp = URL(fileURLWithPath: state.tempFolder.isEmpty ? NSTemporaryDirectory() : state.tempFolder, isDirectory: true)
        PSDrop.collect(providers, tempFolder: temp) { state.addStickers(from: $0) }
        return true
      }
      .focusable()
      .focusEffectDisabled()
      .focused($focused)
      .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .deleteForward, KeyEquivalent("d")]) { press in
        keyPressed(press)
      }
    }
    .aspectRatio(2, contentMode: .fit)
    .onAppear { state.refreshPreview(scale: 1) }
    .onChange(of: state.doc.stickers) { state.refreshPreview(scale: state.isDragging ? 0.5 : 1) }
    .onChange(of: state.isDragging) { _, dragging in if !dragging { state.refreshPreview(scale: 1) } }
  }

  private func pointer(_ size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let p: PSUV = (u: Double(value.location.x / size.width), v: Double(value.location.y / size.height))
        if !pressed {
          pressed = true
          focused = true
          state.pointerDown(at: p, canvas: size)
        } else {
          state.pointerDragged(to: p, canvas: size, shift: NSEvent.modifierFlags.contains(.shift))
        }
      }
      .onEnded { _ in
        pressed = false
        state.pointerUp()
      }
  }

  private func keyPressed(_ press: KeyPress) -> KeyPress.Result {
    let step = press.modifiers.contains(.shift) ? 5.0 : 1.0
    switch press.key {
    case .leftArrow: state.nudge(yaw: -step, pitch: 0)
    case .rightArrow: state.nudge(yaw: step, pitch: 0)
    case .upArrow: state.nudge(yaw: 0, pitch: step)
    case .downArrow: state.nudge(yaw: 0, pitch: -step)
    case .delete, .deleteForward: state.deleteSelected()
    default:
      guard press.modifiers.contains(.command) else { return .ignored }
      state.duplicateSelected()
    }
    return .handled
  }
}

/// What is drawn over the picture.
@MainActor
enum PSOverlay {
  /// The stem from the centre to the rotate handle, as segments in canvas points: the handle is taken to the side of the centre it is nearest to
  /// and, when that leaves the canvas, the segment is repeated one width to the side, so a sticker on the seam shows its stem whole.
  static func stem(from center: PSUV, to handle: PSUV, size: CGSize) -> [(CGPoint, CGPoint)] {
    let a = CGPoint(x: center.u * size.width, y: center.v * size.height)
    let b = PSState.unwrapped(CGPoint(x: handle.u * size.width, y: handle.v * size.height), near: a, width: size.width)
    var segments = [(a, b)]
    if min(a.x, b.x) < 0 { segments.append((CGPoint(x: a.x + size.width, y: a.y), CGPoint(x: b.x + size.width, y: b.y))) }
    if max(a.x, b.x) > size.width { segments.append((CGPoint(x: a.x - size.width, y: a.y), CGPoint(x: b.x - size.width, y: b.y))) }
    return segments
  }

  static func draw(in context: inout GraphicsContext, size: CGSize, state: PSState) {
    func point(_ p: PSUV) -> CGPoint { CGPoint(x: p.u * size.width, y: p.v * size.height) }
    if state.doc.guides {
      var guides = Path()
      guides.move(to: CGPoint(x: 0, y: size.height / 2))
      guides.addLine(to: CGPoint(x: size.width, y: size.height / 2))
      for i in 1..<4 {
        guides.move(to: CGPoint(x: size.width * Double(i) / 4, y: 0))
        guides.addLine(to: CGPoint(x: size.width * Double(i) / 4, y: size.height))
      }
      context.stroke(guides, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
    }
    for sticker in state.doc.stickers where sticker.visible {
      let selected = sticker.id == state.doc.selectedID
      var path = Path()
      for line in PSProjection.outline(of: sticker, aspect: state.aspect(of: sticker)) {
        guard let first = line.first else { continue }
        path.move(to: point(first))
        for p in line.dropFirst() { path.addLine(to: point(p)) }
      }
      context.stroke(path, with: .color(.white.opacity(selected ? 1 : 0.4)), lineWidth: selected ? 2.5 : 1.2)
    }
    guard let selected = state.selected, selected.visible else { return }
    let handles = PSProjection.handles(of: selected, aspect: state.aspect(of: selected))
    var stemPath = Path()
    for (from, to) in stem(from: handles.center, to: handles.rotate, size: size) {
      stemPath.move(to: from)
      stemPath.addLine(to: to)
    }
    context.stroke(stemPath, with: .color(.white), lineWidth: 1.5)
    let rotate = point(handles.rotate)
    context.fill(Path(ellipseIn: CGRect(x: rotate.x - 7, y: rotate.y - 7, width: 14, height: 14)), with: .color(DS.accent))
    context.stroke(Path(ellipseIn: CGRect(x: rotate.x - 7, y: rotate.y - 7, width: 14, height: 14)), with: .color(.white), lineWidth: 1.5)
    for corner in handles.corners {
      let c = point(corner)
      context.fill(Path(CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.white))
    }
    let center = point(handles.center)
    context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(.white))
  }
}
