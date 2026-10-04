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
  public var prompt: String
  public var negativePrompt: String
  public var parameters: GenerationParameters
  /// nil when the preset names no model: the chosen one stays.
  public var model: String?

  /// The tab with the preset on it: the preset's parameters (clamped, triggers filled in) but the tab's own
  /// width and height; the preset's prompt and negative prompt when it has them, the tab's otherwise; its
  /// model when it names one. A side beyond the limit the preset's Tiled Diffusion setting allows comes back
  /// within it, keeping the ratio.
  public static func of(_ preset: Preset, current: GenerationFields, catalog: ModelCatalog) -> PresetLoad {
    var parameters = preset.parameters.clamped().fillingTriggers(from: catalog)
    parameters.width = current.parameters.width
    parameters.height = current.parameters.height
    parameters.fitSizeToLimit()
    return PresetLoad(
      prompt: preset.prompt.isEmpty ? current.prompt : preset.prompt,
      negativePrompt: preset.negativePrompt.isEmpty ? current.negativePrompt : preset.negativePrompt,
      parameters: parameters, model: preset.model.isEmpty ? nil : preset.model)
  }
}
