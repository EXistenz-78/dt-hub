import Foundation

/// How a tile is regenerated for one family of models (spec §2). Only FLUX.2 klein 9B for now; Qwen Image 2.1 is one more
/// entry in `TUPresetTable` when its LoRAs are tried.
struct TUPreset: Equatable, Sendable {
  /// The name the preset has in DT Hub's Preset menu (`TUP ·` is this plug-in's tag, like `SLR ·`).
  let name: String
  let steps: Int
  let guidanceScale: Double
  let sampler: Int
  let shift: Double
  /// How much the tile is changed (0…1): 1, the mask and the overlap keep the join.
  let strength: Double
  let loraFile: String
  let defaultLoRAWeight: Double

  /// The `fields` of a `contribute` message or a pass, with the prompt.
  /// Every value the preset fixes is named, so nothing is left to the Generation tab: with `resolutionDependentShift` on, the
  /// shift would be worked out from the size of the tile instead of staying the preset's.
  func fields(prompt: String) -> [String: Any] {
    [
      "prompt": prompt, "steps": steps, "guidanceScale": guidanceScale, "sampler": sampler, "shift": shift,
      "resolutionDependentShift": false, "cfgZeroStar": false, "cfgZeroInitSteps": 0,
    ]
  }

  func loras(weight: Double) -> [[String: Any]] {
    [["file": loraFile, "weight": weight]]
  }
}

enum TUPresetTable {
  /// Softness and reach of the mask's edge, in pixels (spec §2).
  static let maskBlur = 30.0
  static let maskOutset = 30

  /// The strength a LoRA can have, as in the app's LoRA card (Draw Things accepts −1,5…2,5).
  static let loraWeightRange = -1.5...2.5

  /// The preset for the family the header's model belongs to (`DTHubContext.family`); nil when the plug-in does not know it.
  static func preset(forFamily family: String?) -> TUPreset? {
    switch family {
    case "flux2_9b":
      TUPreset(
        name: "TUP · FLUX.2 klein 9B", steps: 4, guidanceScale: 1, sampler: 16, shift: 3, strength: 1,
        loraFile: "f2_ultra_real_v5_pro_lora_f16.ckpt", defaultLoRAWeight: 1)
    default:
      nil
    }
  }
}

enum TUPrompt {
  static let sentence = "ALSO PRESERVE COLORS AND LUMINOSITY"

  /// The trigger word of the LoRA, then the fixed sentence.
  static func text(trigger: String) -> String {
    let word = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
    return word.isEmpty ? sentence : "\(word) \(sentence)"
  }
}
