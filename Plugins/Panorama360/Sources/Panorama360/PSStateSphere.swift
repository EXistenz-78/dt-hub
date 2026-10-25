import CoreGraphics
import Foundation

extension PSState {
  /// What the sphere view lets the pointer do: with the canvas as the source, the stickers (move, scale, rotate); in every case, turning the view
  /// by dragging the empty part. With the result as the source the view only turns.
  private var editsStickers: Bool { doc.source == .canvas }

  private static let grabRadius = 12.0

  func spherePointerDown(at p: CGPoint, size: CGSize) {
    drag = nil
    let camera = doc.camera
    if editsStickers {
      if let s = selected, s.visible {
        let handles = PSSphere.handles(of: s, aspect: aspect(of: s), camera: camera, size: size)
        if let center = handles.center {
          if let rotate = handles.rotate, hypot(p.x - rotate.x, p.y - rotate.y) < Self.grabRadius {
            drag = .rotate(s.id, center: center, startRot: s.rot, startAngle: atan2(p.y - center.y, p.x - center.x))
            return
          }
          for case let corner? in handles.corners where hypot(p.x - corner.x, p.y - corner.y) < Self.grabRadius {
            drag = .scale(s.id, center: center, startFOV: s.hfov, startDistance: hypot(p.x - center.x, p.y - center.y))
            return
          }
        }
      }
      let pairs = doc.stickers.map { (sticker: $0, aspect: aspect(of: $0)) }
      if let id = PSSphere.hit(at: p, stickers: pairs, camera: camera, size: size), let hit = sticker(id) {
        select(id)
        drag = .move(id, PSInteraction.grab(hit, at: spherePoint(p, camera, size)))
        return
      }
    }
    drag = .look(camera: camera, from: p)
  }

  func spherePointerDragged(to p: CGPoint, size: CGSize, shift: Bool) {
    guard let drag else { return }
    switch drag {
    case .move(let id, let grab):
      let at = spherePoint(p, doc.camera, size)
      update(id) { $0 = PSInteraction.moved($0, to: at, grab: grab) }
    case .scale(let id, let center, let startFOV, let startDistance):
      update(id) {
        $0 = PSInteraction.scaled($0, startFOV: startFOV, startDistance: startDistance, distance: hypot(p.x - center.x, p.y - center.y))
      }
    case .rotate(let id, let center, let startRot, let startAngle):
      update(id) {
        $0 = PSInteraction.rotated(
          $0, startRot: startRot, startAngle: startAngle, angle: atan2(p.y - center.y, p.x - center.x), snap: shift)
      }
    case .look(let camera, let from):
      var turned = camera
      turned.look(dx: Double(p.x - from.x), dy: Double(p.y - from.y), width: Double(size.width))
      mutate { $0.camera = turned }
    }
  }

  func spherePointerUp() { drag = nil }

  func sphereZoom(by delta: Double) {
    var camera = doc.camera
    camera.zoom(by: delta)
    mutate { $0.camera = camera }
  }

  func resetCamera() { mutate { $0.camera = PSCamera() } }

  /// The point of the ERP (u, v) under a point of the view.
  private func spherePoint(_ p: CGPoint, _ camera: PSCamera, _ size: CGSize) -> PSUV {
    PSProjection.point(of: camera.ray(x: Double(p.x), y: Double(p.y), width: Double(size.width), height: Double(size.height)))
  }
}
