import AppKit
import SwiftUI

/// What the plug-in remembers between runs: the lights (and whether each block is open) and the two boxes.
struct SLRSession: Equatable {
  static let maxLights = 3

  var lights: [LightParams]
  var expanded: [UUID: Bool]
  var overcast: Bool
  var saveToDesktop: Bool

  /// A first run: the two default lights, both open, both boxes off.
  static func initial() -> SLRSession {
    let lights = [LightParams.makeDefault(index: 0), LightParams.makeDefault(index: 1)]
    return SLRSession(
      lights: lights, expanded: Dictionary(uniqueKeysWithValues: lights.map { ($0.id, true) }),
      overcast: false, saveToDesktop: false)
  }
}

/// The session in `UserDefaults`. `Color` is not `Codable`, so it goes through plain RGB components.
struct SLRStore {
  static let key = "com.exiztenz.dthub.spherelight.state.v1"

  var defaults: UserDefaults = .standard
  var key: String = SLRStore.key

  private struct SavedLight: Codable {
    var id: UUID
    var rotationDeg: Double
    var elevationDeg: Double
    var intensity: Double
    var hardness: Double
    var colorR: Double
    var colorG: Double
    var colorB: Double
    var expanded: Bool
  }

  private struct Saved: Codable {
    var lights: [SavedLight]
    var overcast: Bool
    var saveToDesktop: Bool
  }

  func save(_ session: SLRSession) {
    let lights = session.lights.map { light -> SavedLight in
      let c = Self.components(of: light.color)
      return SavedLight(
        id: light.id, rotationDeg: light.rotationDeg, elevationDeg: light.elevationDeg,
        intensity: light.intensity, hardness: light.hardness, colorR: c.r, colorG: c.g, colorB: c.b,
        expanded: session.expanded[light.id, default: true])
    }
    let saved = Saved(lights: lights, overcast: session.overcast, saveToDesktop: session.saveToDesktop)
    guard let data = try? JSONEncoder().encode(saved) else { return }
    defaults.set(data, forKey: key)
  }

  /// The saved session; nil when there is none, it cannot be read or it has no lights.
  func load() -> SLRSession? {
    guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data),
      !saved.lights.isEmpty
    else { return nil }
    var lights: [LightParams] = []
    var expanded: [UUID: Bool] = [:]
    for item in saved.lights.prefix(SLRSession.maxLights) {
      lights.append(
        LightParams(
          id: item.id, rotationDeg: item.rotationDeg, elevationDeg: item.elevationDeg,
          intensity: item.intensity, hardness: item.hardness,
          color: Color(red: item.colorR, green: item.colorG, blue: item.colorB)))
      expanded[item.id] = item.expanded
    }
    return SLRSession(lights: lights, expanded: expanded, overcast: saved.overcast, saveToDesktop: saved.saveToDesktop)
  }

  private static func components(of color: Color) -> (r: Double, g: Double, b: Double) {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
    return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
  }
}
