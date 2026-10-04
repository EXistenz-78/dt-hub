import SwiftUI

/// A 3D vector for the ray tracer.
struct Vec3 {
  var x: Double
  var y: Double
  var z: Double

  static let zero = Vec3(x: 0, y: 0, z: 0)

  var length: Double { (x * x + y * y + z * z).squareRoot() }

  func normalized() -> Vec3 {
    let len = length
    guard len > 0 else { return self }
    return Vec3(x: x / len, y: y / len, z: z / len)
  }

  func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }

  func cross(_ o: Vec3) -> Vec3 {
    Vec3(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
  }

  static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
  static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
  static func * (a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }
}

/// One light's editable parameters. Intensity (brightness) and hardness (shadow-edge sharpness) are independent.
struct LightParams: Identifiable, Equatable {
  let id: UUID
  var rotationDeg: Double
  var elevationDeg: Double
  var intensity: Double  // 0.2...3
  var hardness: Double  // 0 (soft) ... 1 (hard)
  var color: Color

  init(
    id: UUID = UUID(), rotationDeg: Double, elevationDeg: Double, intensity: Double,
    hardness: Double, color: Color
  ) {
    self.id = id
    self.rotationDeg = rotationDeg
    self.elevationDeg = elevationDeg
    self.intensity = intensity
    self.hardness = hardness
    self.color = color
  }

  /// The lights a new session starts with (index 0, 1) and the one the "+" button adds (index 2).
  static func makeDefault(index: Int) -> LightParams {
    switch index {
    case 0:
      return LightParams(
        rotationDeg: -135, elevationDeg: 27, intensity: 1.5, hardness: 0.65, color: .white)
    case 1:
      return LightParams(
        rotationDeg: 70, elevationDeg: 55, intensity: 0.7, hardness: 0.4, color: .white)
    default:
      return LightParams(
        rotationDeg: 175, elevationDeg: 25, intensity: 0.6, hardness: 0.3, color: .white)
    }
  }
}
