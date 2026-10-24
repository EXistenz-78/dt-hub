import Foundation

/// What the plug-in reads from the preset file the user may have changed (`~/Library/Application Support/DT Hub/Presets/<name>.json`):
/// the app never touches a preset that already exists, so the file is the user's. Everything else in it (steps, guidance,
/// sampler, shift…) is applied by the app from the file itself; the plug-in needs only the prompt, to add the user's
/// instructions to it, and the first LoRA, to give it the strength of the slider.
struct TUPresetFile: Equatable, Sendable {
  var prompt: String?
  var loraFile: String?

  /// ~/Library/Application Support/DT Hub/Presets (the app's folder).
  static var appFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("Presets", isDirectory: true)
  }

  /// Nil without a folder, without the file or when it is not a JSON object.
  static func read(named name: String, in folder: URL?) -> TUPresetFile? {
    guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).json")),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    let loras = (root["parameters"] as? [String: Any])?["loras"] as? [[String: Any]]
    return TUPresetFile(prompt: root["prompt"] as? String, loraFile: loras?.first?["file"] as? String)
  }
}
