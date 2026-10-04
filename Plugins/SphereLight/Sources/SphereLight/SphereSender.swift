import Foundation

/// The two buttons of the tab, apart from the screen: render the sphere, write it where the app can read it, keep a
/// copy on the Desktop if asked, and contribute. It talks to the app through closures, so a test can stand in for it.
@MainActor
struct SphereSender {
  enum Kind { case pipeline, moodboard }

  /// `host.contribute` / `host.registerPresets`.
  var contribute: @MainActor ([String: Any]) async -> [String: Any]?
  var registerPresets: @MainActor ([[String: Any]]) async -> [String: Any]?
  var saveFolder: URL = DesktopSaver.desktopFolder
  var size = 1024
  var shadowSamples = 16
  var italian = L.systemIsItalian

  static let fileName = "com.exiztenz.dthub.spherelight-sphere.png"

  /// Does the whole job and returns the line to show under the buttons.
  func send(_ kind: Kind, lights: [LightParams], overcast: Bool, saveToDesktop: Bool, tempFolder: String?) async -> String {
    guard let tempFolder else { return L.text(.noFolder, italian: italian) }
    let (size, samples) = (size, shadowSamples)
    let pixels = await Task.detached(priority: .userInitiated) {
      SphereRenderer.render(width: size, height: size, lights: lights, shadowSampleCount: samples)
    }.value
    guard let png = SphereRenderer.pngData(fromRGB8: pixels, width: size, height: size) else {
      return L.text(.renderFailed, italian: italian)
    }
    let path = (tempFolder as NSString).appendingPathComponent(Self.fileName)
    do {
      try FileManager.default.createDirectory(atPath: tempFolder, withIntermediateDirectories: true)
      try png.write(to: URL(fileURLWithPath: path))
    } catch {
      return L.text(.renderFailed, italian: italian)
    }

    var lines: [String] = []
    if saveToDesktop {
      if let saved = try? DesktopSaver.save(png, in: saveFolder) {
        lines.append(L.format(.savedDesktop, saved.lastPathComponent, italian: italian))
      } else {
        lines.append(L.text(.saveFailed, italian: italian))
      }
    }

    let answer: [String: Any]?
    switch kind {
    case .pipeline:
      // The presets are offered again (a name the menu has is never touched), in case the user deleted one.
      _ = await registerPresets(SLRMessages.presets())
      answer = await contribute(["pipeline": SLRMessages.pipeline(overcast: overcast, spherePath: path)])
    case .moodboard:
      answer = await contribute(["moodboard": SLRMessages.moodboard(spherePath: path)])
    }
    lines.insert(Self.describe(answer, italian: italian), at: 0)
    return lines.joined(separator: " ")
  }

  static func describe(_ answer: [String: Any]?, italian: Bool) -> String {
    guard let answer else { return L.text(.notAnswered, italian: italian) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? L.text(.notAnswered, italian: italian) }
    let conflicts = answer["conflicts"] as? Int ?? 0
    return conflicts > 0 ? L.format(.sentWithConflicts, conflicts, italian: italian) : L.text(.sent, italian: italian)
  }
}
