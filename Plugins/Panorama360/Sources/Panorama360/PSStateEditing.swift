import CoreGraphics
import Foundation
import SwiftUI

/// What the pointer is doing to a sticker (see `PSState.pointerDown`).
enum PSDrag {
  case move(UUID, PSInteraction.Grab)
  case scale(UUID, center: CGPoint, startFOV: Double, startDistance: Double)
  case rotate(UUID, center: CGPoint, startRot: Double, startAngle: Double)
}

extension PSState {
  // MARK: Reading

  var selected: Sticker? { doc.selectedID.flatMap(sticker) }

  func sticker(_ id: UUID) -> Sticker? { doc.stickers.first { $0.id == id } }

  func image(for sticker: Sticker) -> CGImage? {
    images.image(for: sticker.id, loading: projectFolder?.appendingPathComponent(sticker.file))
  }

  func setImage(_ image: CGImage, for id: UUID) { images.set(image, for: id) }

  /// Width / height of the sticker's picture (1.5 until it is known).
  func aspect(of sticker: Sticker) -> Double {
    guard let image = image(for: sticker), image.height > 0 else { return 1.5 }
    return Double(image.width) / Double(image.height)
  }

  /// The layers to draw: the visible stickers whose picture is there, in order.
  func layers() -> [PSLayer] {
    doc.stickers.compactMap { sticker in
      guard sticker.visible, let image = image(for: sticker) else { return nil }
      return PSLayer(
        image: image, basis: PSProjection.basis(for: sticker, aspect: Double(image.width) / Double(image.height)),
        opacity: sticker.opacity)
    }
  }

  func renderedERP(width: Int, height: Int, uOffset: Double = 0) throws -> CGImage {
    try PSRendererFactory.make().render(layers(), width: width, height: height, uOffset: uOffset)
  }

  /// Draws the canvas picture in the background; a newer request makes an older answer be dropped.
  func refreshPreview(scale: Double) {
    previewGeneration += 1
    let generation = previewGeneration
    let layers = layers()
    let width = Int(1024 * scale), height = Int(512 * scale)
    Task.detached(priority: .userInitiated) { [weak self] in
      let image = try? PSRendererFactory.make().render(layers, width: width, height: height, uOffset: 0)
      await MainActor.run {
        guard let self, self.previewGeneration == generation, let image else { return }
        self.preview = image
      }
    }
  }

  // MARK: Writing

  func select(_ id: UUID?) { mutate { $0.selectedID = id } }

  func update(_ id: UUID, _ change: (inout Sticker) -> Void) {
    mutate { doc in
      if let index = doc.stickers.firstIndex(where: { $0.id == id }) { change(&doc.stickers[index]) }
    }
  }

  /// A field of a sticker that always reads the state, never a copy the view was drawn with.
  func binding(_ id: UUID, _ keyPath: WritableKeyPath<Sticker, Double>) -> Binding<Double> {
    Binding(
      get: { self.sticker(id)?[keyPath: keyPath] ?? 0 },
      set: { value in self.update(id) { $0[keyPath: keyPath] = value } })
  }

  func nudge(yaw: Double, pitch: Double) {
    guard let id = doc.selectedID else { return }
    update(id) {
      $0.yaw = PSProjection.wrapYaw($0.yaw + yaw)
      $0.pitch = min(89, max(-89, $0.pitch + pitch))
    }
  }

  func deleteSelected() {
    guard let id = doc.selectedID, let index = doc.stickers.firstIndex(where: { $0.id == id }) else { return }
    mutate {
      $0.stickers.remove(at: index)
      $0.selectedID = $0.stickers.isEmpty ? nil : $0.stickers[max(0, index - 1)].id
    }
    images.remove(id)
  }

  func duplicateSelected() {
    guard let original = selected, let index = doc.stickers.firstIndex(where: { $0.id == original.id }) else { return }
    var copy = original
    copy.id = UUID()
    copy.yaw = PSProjection.wrapYaw(original.yaw + 10)
    if let image = image(for: original) { images.set(image, for: copy.id) }
    mutate {
      $0.stickers.insert(copy, at: index + 1)
      $0.selectedID = copy.id
    }
  }

  func clearAll() {
    mutate {
      $0.stickers = []
      $0.selectedID = nil
    }
    images.removeAll()
  }

  // MARK: The pointer (u, v are fractions of the canvas; `canvas` is its size in points)

  private static let grabRadius = 12.0

  func pointerDown(at p: PSUV, canvas: CGSize) {
    drag = nil
    let pointer = CGPoint(x: p.u * canvas.width, y: p.v * canvas.height)
    func point(_ q: PSUV) -> CGPoint { CGPoint(x: q.u * canvas.width, y: q.v * canvas.height) }
    if let s = selected, s.visible {
      let handles = PSProjection.handles(of: s, aspect: aspect(of: s))
      let center = point(handles.center)
      if hypot(pointer.x - point(handles.rotate).x, pointer.y - point(handles.rotate).y) < Self.grabRadius {
        drag = .rotate(s.id, center: center, startRot: s.rot, startAngle: atan2(pointer.y - center.y, pointer.x - center.x))
        return
      }
      for corner in handles.corners where hypot(pointer.x - point(corner).x, pointer.y - point(corner).y) < Self.grabRadius {
        drag = .scale(
          s.id, center: center, startFOV: s.hfov, startDistance: hypot(pointer.x - center.x, pointer.y - center.y))
        return
      }
    }
    let pairs = doc.stickers.map { (sticker: $0, aspect: aspect(of: $0)) }
    guard let id = PSProjection.hitTest(u: p.u, v: p.v, stickers: pairs), let hit = sticker(id) else { return }
    select(id)
    drag = .move(id, PSInteraction.grab(hit, at: p))
  }

  func pointerDragged(to p: PSUV, canvas: CGSize, shift: Bool) {
    guard let drag else { return }
    let pointer = CGPoint(x: p.u * canvas.width, y: p.v * canvas.height)
    switch drag {
    case .move(let id, let grab):
      update(id) { $0 = PSInteraction.moved($0, to: p, grab: grab) }
    case .scale(let id, let center, let startFOV, let startDistance):
      update(id) {
        $0 = PSInteraction.scaled(
          $0, startFOV: startFOV, startDistance: startDistance, distance: hypot(pointer.x - center.x, pointer.y - center.y))
      }
    case .rotate(let id, let center, let startRot, let startAngle):
      update(id) {
        $0 = PSInteraction.rotated(
          $0, startRot: startRot, startAngle: startAngle, angle: atan2(pointer.y - center.y, pointer.x - center.x), snap: shift)
      }
    }
  }

  func pointerUp() { drag = nil }
}
