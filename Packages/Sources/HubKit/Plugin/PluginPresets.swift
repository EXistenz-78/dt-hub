import Foundation

/// The `presets` message (plug-in → app): presets for the Preset menu, each a name, `fields` (the keys of
/// `contribute`, the prompt and the negative prompt among them; a width or height is ignored: a preset has
/// no size) and `loras`. What a preset does not say is the default. A plug-in never names a model.
public struct PluginPresets: Equatable, Sendable {
  public var presets: [Preset]

  /// Nil when the data is not a JSON object with a `presets` list. An entry without a name is left out.
  /// The name carries the plug-in's acronym (e.g. "SMP · Overcast"): the app adds nothing to say where it comes from.
  public init?(message: Data) {
    guard let root = try? JSONDecoder().decode(JSONValue.self, from: message), case .object(let object) = root,
      case .array(let list)? = object["presets"]
    else { return nil }
    presets = list.compactMap { value in
      guard case .object(let entry) = value, case .string(let raw)? = entry["name"] else { return nil }
      let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      var overlay = FieldOverlay()
      if case .object(let json)? = entry["fields"] { overlay = FieldOverlay(json: json) }
      var fields = overlay.applied(to: GenerationFields())
      fields.parameters.loras = PluginContribution.loras(entry["loras"]) ?? []
      return Preset(
        name: name, prompt: fields.prompt, negativePrompt: fields.negativePrompt, parameters: fields.parameters)
    }
  }
}
