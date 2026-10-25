import Foundation

struct Vec3: Equatable, Sendable {
  var x: Double
  var y: Double
  var z: Double

  func dot(_ other: Vec3) -> Double { x * other.x + y * other.y + z * other.z }
  func cross(_ other: Vec3) -> Vec3 { Vec3(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x) }
  static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
  static func * (a: Vec3, k: Double) -> Vec3 { Vec3(x: a.x * k, y: a.y * k, z: a.z * k) }
  var normalized: Vec3 { let n = dot(self).squareRoot(); return n > 0 ? self * (1 / n) : self }
}

/// The frame of a sticker: where it looks, its axes and the tangents of its half angles (`tanX` horizontal, `tanY` vertical).
struct StickerBasis: Equatable, Sendable {
  var forward: Vec3
  var right: Vec3
  var up: Vec3
  var tanX: Double
  var tanY: Double
}

typealias PSUV = (u: Double, v: Double)

struct PSHandles {
  var center: PSUV
  /// Top-left, top-right, bottom-right, bottom-left.
  var corners: [PSUV]
  var rotate: PSUV
}

/// The maths of the panorama (spec §3.2). Axes: +X right, +Y up, +Z ahead. A column `u` and a row `v` are fractions (0…1) of the
/// ERP's width and height; `uOffset` is a horizontal shift in turns (0 now: the seam correction will roll the picture by half a turn).
enum PSProjection {
  static let degrees = Double.pi / 180
  /// The diagonal of a 35 mm frame, in millimetres.
  static let diagonal35 = (36.0 * 36 + 24 * 24).squareRoot()

  static func direction(u: Double, v: Double, uOffset: Double = 0) -> Vec3 {
    let lon = (u + uOffset - 0.5) * 2 * .pi
    let lat = (0.5 - v) * .pi
    return Vec3(x: sin(lon) * cos(lat), y: sin(lat), z: cos(lon) * cos(lat))
  }

  static func point(of d: Vec3, uOffset: Double = 0) -> PSUV {
    let lon = atan2(d.x, d.z)
    let lat = asin(min(1, max(-1, d.y)))
    let u = lon / (2 * .pi) + 0.5 - uOffset
    return (u: u - u.rounded(.down), v: 0.5 - lat / .pi)
  }

  static func basis(for sticker: Sticker, aspect: Double) -> StickerBasis {
    let y = sticker.yaw * degrees, p = sticker.pitch * degrees, r = sticker.rot * degrees
    let forward = Vec3(x: sin(y) * cos(p), y: sin(p), z: cos(y) * cos(p))
    let right0 = Vec3(x: cos(y), y: 0, z: -sin(y))
    let up0 = forward.cross(right0)
    let tanX = tan(sticker.hfov * degrees / 2)
    return StickerBasis(
      forward: forward, right: right0 * cos(r) + up0 * -sin(r), up: right0 * sin(r) + up0 * cos(r), tanX: tanX,
      tanY: tanX / aspect)
  }

  /// Where a direction falls on the sticker's picture (`s` across, `t` down, both 0…1), or nil outside it or behind it.
  static func planeCoords(_ d: Vec3, in basis: StickerBasis) -> (s: Double, t: Double)? {
    let dz = d.dot(basis.forward)
    guard dz > 1e-5 else { return nil }
    let s = d.dot(basis.right) / dz / basis.tanX * 0.5 + 0.5
    let t = 0.5 - d.dot(basis.up) / dz / basis.tanY * 0.5
    return (0...1).contains(s) && (0...1).contains(t) ? (s: s, t: t) : nil
  }

  /// The vertical field of view, in degrees, of a picture with this horizontal one and this width / height.
  static func verticalFOV(hfov: Double, aspect: Double) -> Double {
    2 * atan(tan(hfov * degrees / 2) / aspect) / degrees
  }

  /// The horizontal field of view, in degrees, of a photo taken with this 35 mm equivalent focal length (which already holds the
  /// crop factor of the sensor), for a picture of this width / height. Clamped to what a sticker can be (5…170°).
  static func horizontalFOV(focal35mm: Double, aspect: Double) -> Double {
    let width = diagonal35 * aspect / (1 + aspect * aspect).squareRoot()
    return min(170, max(5, 2 * atan(width / (2 * focal35mm)) / degrees))
  }

  /// An angle brought into (−180, 180].
  static func wrapYaw(_ degrees: Double) -> Double {
    var value = degrees.truncatingRemainder(dividingBy: 360)
    if value > 180 { value -= 360 }
    if value <= -180 { value += 360 }
    return value
  }

  /// The topmost visible sticker under the point (`stickers` in layer order: the last is on top).
  static func hitTest(u: Double, v: Double, stickers: [(sticker: Sticker, aspect: Double)], uOffset: Double = 0) -> UUID? {
    let d = direction(u: u, v: v, uOffset: uOffset)
    for entry in stickers.reversed() where entry.sticker.visible {
      if planeCoords(d, in: basis(for: entry.sticker, aspect: entry.aspect)) != nil { return entry.sticker.id }
    }
    return nil
  }

  /// The border of the sticker as lines in (u, v), cut wherever the border crosses the seam of the picture.
  static func outline(of sticker: Sticker, aspect: Double, samplesPerEdge: Int = 28, uOffset: Double = 0) -> [[PSUV]] {
    let b = basis(for: sticker, aspect: aspect)
    let corners: [(Double, Double)] = [(-1, 1), (1, 1), (1, -1), (-1, -1), (-1, 1)]
    var points: [PSUV] = []
    for (a, c) in zip(corners, corners.dropFirst()) {
      for i in 0..<samplesPerEdge {
        let k = Double(i) / Double(samplesPerEdge)
        points.append(point(of: ray(b, x: a.0 + (c.0 - a.0) * k, y: a.1 + (c.1 - a.1) * k), uOffset: uOffset))
      }
    }
    points.append(point(of: ray(b, x: -1, y: 1), uOffset: uOffset))
    var lines: [[PSUV]] = [[]]
    for p in points {
      if let last = lines[lines.count - 1].last, abs(last.u - p.u) > 0.5 { lines.append([]) }
      lines[lines.count - 1].append(p)
    }
    return lines
  }

  static func handles(of sticker: Sticker, aspect: Double, uOffset: Double = 0) -> PSHandles {
    let b = basis(for: sticker, aspect: aspect)
    return PSHandles(
      center: point(of: b.forward, uOffset: uOffset),
      corners: [(-1.0, 1.0), (1, 1), (1, -1), (-1, -1)].map { point(of: ray(b, x: $0.0, y: $0.1), uOffset: uOffset) },
      rotate: point(of: ray(b, x: 0, y: 1.35), uOffset: uOffset))
  }

  /// The direction through the point (`x`, `y`) of the sticker's plane, in half widths and half heights (y up).
  private static func ray(_ b: StickerBasis, x: Double, y: Double) -> Vec3 {
    (b.forward + b.right * (x * b.tanX) + b.up * (y * b.tanY)).normalized
  }
}
