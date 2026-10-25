import CoreGraphics
import Foundation

/// Outlines, handles and picking of the stickers seen from a camera in the centre of the sphere. Everything is in view points (0, 0 top left).
enum PSSphere {
  /// The border of the sticker as lines in view points. Lines are cut where the border goes behind the camera (it is a great-circle arc: between two
  /// points in front it stays in front), so none crosses the view.
  static func outline(of sticker: Sticker, aspect: Double, camera: PSCamera, size: CGSize, samplesPerEdge: Int = 28) -> [[CGPoint]] {
    let b = PSProjection.basis(for: sticker, aspect: aspect)
    let corners: [(Double, Double)] = [(-1, 1), (1, 1), (1, -1), (-1, -1), (-1, 1)]
    var lines: [[CGPoint]] = []
    var current: [CGPoint] = []
    func add(_ x: Double, _ y: Double) {
      if let p = camera.screenPoint(of: PSProjection.ray(b, x: x, y: y), width: size.width, height: size.height) {
        current.append(p)
      } else if !current.isEmpty {
        lines.append(current)
        current = []
      }
    }
    for (a, c) in zip(corners, corners.dropFirst()) {
      for i in 0..<samplesPerEdge {
        let k = Double(i) / Double(samplesPerEdge)
        add(a.0 + (c.0 - a.0) * k, a.1 + (c.1 - a.1) * k)
      }
    }
    add(-1, 1)
    if !current.isEmpty { lines.append(current) }
    return lines
  }

  /// The centre, the four corners (top-left, top-right, bottom-right, bottom-left) and the rotate handle; nil where they are behind the camera.
  static func handles(of sticker: Sticker, aspect: Double, camera: PSCamera, size: CGSize)
    -> (center: CGPoint?, corners: [CGPoint?], rotate: CGPoint?)
  {
    let b = PSProjection.basis(for: sticker, aspect: aspect)
    func point(_ d: Vec3) -> CGPoint? { camera.screenPoint(of: d, width: size.width, height: size.height) }
    return (
      point(b.forward), [(-1.0, 1.0), (1, 1), (1, -1), (-1, -1)].map { point(PSProjection.ray(b, x: $0.0, y: $0.1)) },
      point(PSProjection.ray(b, x: 0, y: 1.35))
    )
  }

  /// The topmost visible sticker under a point of the view.
  static func hit(at p: CGPoint, stickers: [(sticker: Sticker, aspect: Double)], camera: PSCamera, size: CGSize) -> UUID? {
    PSProjection.hitTest(
      direction: camera.ray(x: Double(p.x), y: Double(p.y), width: Double(size.width), height: Double(size.height)),
      stickers: stickers)
  }
}
