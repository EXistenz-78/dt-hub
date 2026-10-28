// Copied from Plugins/Panorama360 (2026-10-28): Sticker (the projection's basis is made from it).
import Foundation

/// One picture placed on the panorama. The angles are in degrees; `file` is relative to the project folder.
struct Sticker: Codable, Equatable, Hashable, Identifiable, Sendable {
  var id = UUID()
  var name: String
  var file: String
  var yaw = 0.0
  var pitch = 0.0
  var rot = 0.0
  /// The horizontal field of view; the vertical one comes from the picture's proportions and is never stored.
  var hfov = 60.0
  var opacity = 1.0
  var visible = true

  /// Brings every value into its range: angles into (−180, 180], pitch to ±89°, field of view to 5…170°, opacity to 0…1.
  mutating func clampValues() {
    yaw = PSProjection.wrapYaw(yaw)
    rot = PSProjection.wrapYaw(rot)
    pitch = min(89, max(-89, pitch))
    hfov = min(170, max(5, hfov))
    opacity = min(1, max(0, opacity))
  }
}
