import Foundation
import HubKit

/// What an imported file gave.
public struct PresetImportResult: Equatable, Sendable {
  public var presets: [Preset]
  /// Entries that were not a preset (no name, no configuration, a configuration that does not
  /// apply).
  public var skipped: Int

  public init(presets: [Preset], skipped: Int) {
    self.presets = presets
    self.skipped = skipped
  }
}

/// Reads a file with a list of presets: a JSON array of `{"name", "configuration", "negative"?}`
/// objects, the shape of Draw Things' `custom_configs.json` and of its public list of
/// configurations (spec §6).
public enum PresetImport {
  public static func read(_ data: Data, codec: any ConfigurationCodec) -> PresetImportResult {
    guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
      return PresetImportResult(presets: [], skipped: 1)
    }
    var presets: [Preset] = []
    var skipped = 0
    for entry in entries {
      guard let object = entry as? [String: Any],
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
        let configuration = object["configuration"] as? [String: Any],
        let json = (try? JSONSerialization.data(withJSONObject: configuration)).map({ String(decoding: $0, as: UTF8.self) }),
        let state = try? codec.apply(json: json, to: ConfigurationState(model: "", parameters: .default))
      else {
        skipped += 1
        continue
      }
      presets.append(
        Preset(
          name: name, model: state.model, negativePrompt: object["negative"] as? String ?? "",
          parameters: state.parameters))
    }
    return PresetImportResult(presets: presets, skipped: skipped)
  }
}

extension GenerationParameters {
  /// LoRAs without a trigger word get the one the server's metadata names: the Draw Things
  /// JSON has none.
  public func fillingTriggers(from catalog: ModelCatalog) -> GenerationParameters {
    var copy = self
    for index in copy.loras.indices where copy.loras[index].trigger.isEmpty {
      copy.loras[index].trigger = catalog.lora(forFile: copy.loras[index].file)?.trigger ?? ""
    }
    return copy
  }
}

/// What loading a preset puts on the tab.
public struct PresetLoad: Equatable, Sendable {
  public var parameters: GenerationParameters
  public var negativePrompt: String
  /// nil when the preset names no model: the chosen one stays.
  public var model: String?

  /// The preset's parameters (clamped, triggers filled in), its negative prompt when it has
  /// one, its model when it names one. The prompt is never touched.
  public static func of(_ preset: Preset, currentNegativePrompt: String, catalog: ModelCatalog) -> PresetLoad {
    PresetLoad(
      parameters: preset.parameters.clamped().fillingTriggers(from: catalog),
      negativePrompt: preset.negativePrompt.isEmpty ? currentNegativePrompt : preset.negativePrompt,
      model: preset.model.isEmpty ? nil : preset.model)
  }
}
