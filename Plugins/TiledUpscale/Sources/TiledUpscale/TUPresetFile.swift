import Foundation

/// What the plug-in reads from the preset file the user may have changed (`~/Library/Application Support/DT Hub/Presets/<name>.json`):
/// the app never touches a preset that already exists, so the file is the user's. Everything else in it (steps, guidance,
/// sampler, shift…) is applied by the app from the file itself; the plug-in needs only the prompt, to add the user's
/// instructions to it, and the first LoRA, to give it the strength of the slider.
struct TUPresetFile: Equatable, Sendable {
  var prompt: String?
  var loraFile: String?
  var loraWeight: Double?
  var steps: Int?
  var guidanceScale: Double?
  var sampler: Int?
  var shift: Double?
  var resolutionDependentShift: Bool?

  /// The tag of the presets this plug-in can use: the ones whose name starts with it (`TUP · FLUX.3 klein`, `TUP my model`…).
  static let namePrefix = "TUP"

  /// The names (without `.json`) of the presets in the folder whose name starts with `TUP`, in alphabetical order.
  static func names(in folder: URL?) -> [String] {
    guard let folder, let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
    return files.filter { $0.hasPrefix(namePrefix) && $0.hasSuffix(".json") }
      .map { String($0.dropLast(".json".count)) }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

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
    let parameters = root["parameters"] as? [String: Any]
    let loras = parameters?["loras"] as? [[String: Any]]
    return TUPresetFile(
      prompt: root["prompt"] as? String, loraFile: loras?.first?["file"] as? String,
      loraWeight: (loras?.first?["weight"] as? NSNumber)?.doubleValue, steps: (parameters?["steps"] as? NSNumber)?.intValue,
      guidanceScale: (parameters?["guidanceScale"] as? NSNumber)?.doubleValue,
      sampler: (parameters?["sampler"] as? NSNumber)?.intValue, shift: (parameters?["shift"] as? NSNumber)?.doubleValue,
      resolutionDependentShift: parameters?["resolutionDependentShift"] as? Bool)
  }
}
