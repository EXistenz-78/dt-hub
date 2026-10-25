import Foundation

/// What a pointer does to a sticker, as pure functions of positions (u, v are fractions of the ERP, 0…1).
enum PSInteraction {
  /// The offset, in degrees, between the point of the sticker that was grabbed and its centre.
  struct Grab: Equatable {
    var yaw: Double
    var pitch: Double
  }

  static func lonLat(_ p: PSUV) -> (lon: Double, lat: Double) { ((p.u - 0.5) * 360, (0.5 - p.v) * 180) }

  static func grab(_ sticker: Sticker, at p: PSUV) -> Grab {
    let ll = lonLat(p)
    return Grab(yaw: PSProjection.wrapYaw(ll.lon - sticker.yaw), pitch: ll.lat - sticker.pitch)
  }

  /// The sticker moved so the grabbed point is under the pointer; crossing the seam wraps the yaw, the pitch stops at ±89°.
  static func moved(_ sticker: Sticker, to p: PSUV, grab: Grab) -> Sticker {
    let ll = lonLat(p)
    var copy = sticker
    copy.yaw = PSProjection.wrapYaw(ll.lon - grab.yaw)
    copy.pitch = min(89, max(-89, ll.lat - grab.pitch))
    return copy
  }

  /// The field of view scaled by how much farther (or nearer) the pointer is from the centre than it was at the start; 5…170°.
  static func scaled(_ sticker: Sticker, startFOV: Double, startDistance: Double, distance: Double) -> Sticker {
    var copy = sticker
    guard startDistance > 0 else { return copy }
    copy.hfov = min(170, max(5, startFOV * distance / startDistance))
    return copy
  }

  /// The rotation follows the angle of the pointer around the centre (radians); `snap` rounds it to steps of 45°.
  static func rotated(_ sticker: Sticker, startRot: Double, startAngle: Double, angle: Double, snap: Bool) -> Sticker {
    var rot = startRot + (angle - startAngle) * 180 / .pi
    if snap { rot = (rot / 45).rounded() * 45 }
    var copy = sticker
    copy.rot = PSProjection.wrapYaw(rot)
    return copy
  }
}
