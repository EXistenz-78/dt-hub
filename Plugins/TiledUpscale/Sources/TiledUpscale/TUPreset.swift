import Foundation

/// How a tile is regenerated for one family of models (spec §2). FLUX.2 klein 9B, FLUX.3 klein and Qwen Image 2.1.
struct TUPreset: Equatable, Sendable {
  /// The name the preset has in DT Hub's Preset menu (`TUP ·` is this plug-in's tag, like `SLR ·`).
  let name: String
  let steps: Int
  let guidanceScale: Double
  let sampler: Int
  let shift: Double
  /// How much the tile is changed (0…1): 1, the mask and the overlap keep the join.
  let strength: Double
  /// The LoRA of the preset; empty when it has none.
  let loraFile: String
  let defaultLoRAWeight: Double
  /// Whether the shift is worked out from the size of the tile (FLUX.2 klein and Qwen Turbo: no, the shift stays the preset's).
  let resolutionDependentShift: Bool
  /// The prompt of every tile when the preset has its own; nil: the trigger word of the LoRA and `TUPrompt.sentence`.
  let fixedPrompt: String?
  /// The model file the preset loads when it is picked in DT Hub (empty: the preset leaves the model as it is).
  var modelFile = ""

  /// The prompt of a tile.
  func prompt(trigger: String) -> String { fixedPrompt ?? TUPrompt.text(trigger: trigger) }

  /// The `fields` of a `contribute` message or a pass, with the prompt.
  /// Every value the preset fixes is named, so nothing is left to the Generation tab: with `resolutionDependentShift` on, the
  /// shift would be worked out from the size of the tile instead of staying the preset's.
  func fields(prompt: String) -> [String: Any] {
    [
      "prompt": prompt, "steps": steps, "guidanceScale": guidanceScale, "sampler": sampler, "shift": shift,
      "resolutionDependentShift": resolutionDependentShift, "cfgZeroStar": false, "cfgZeroInitSteps": 0,
    ]
  }

  /// `["model": file]` for the `presets` message when the preset names a model, else nothing.
  var modelEntry: [String: Any] { modelFile.isEmpty ? [:] : ["model": modelFile] }

  /// The entry of the `presets` message: name, fields, LoRA and, when the preset names one, its model.
  func registration(loraWeight: Double) -> [String: Any] {
    var entry: [String: Any] = ["name": name, "fields": fields(prompt: prompt(trigger: "")), "loras": loras(weight: loraWeight)]
    if !modelFile.isEmpty { entry["model"] = modelFile }
    return entry
  }

  func loras(weight: Double) -> [[String: Any]] {
    loraFile.isEmpty ? [] : [["file": loraFile, "weight": weight]]
  }

  /// The `fields` of a pass: nothing, so the app runs the preset as the user saved it; only when the user wrote instructions,
  /// the prompt of the preset (the file's, else the table's) followed by them.
  func passFields(extra: String, file: TUPresetFile?) -> [String: Any] {
    let added = extra.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !added.isEmpty else { return [:] }
    return ["prompt": TUPrompt.compose(file?.prompt ?? prompt(trigger: ""), extra: added)]
  }

  /// The LoRA of a pass: the preset's own (the first of the file, else the table's) with the strength of the slider.
  func passLoras(weight: Double, file: TUPresetFile?) -> [[String: Any]] {
    let name = file?.loraFile ?? loraFile
    return name.isEmpty ? [] : [["file": name, "weight": weight]]
  }
}

extension TUPreset {
  /// A preset the user made in DT Hub (its name starts with `TUP`): what the plug-in needs comes from its file. Without a LoRA
  /// in the file the pass has none (`loraFile` empty) and the strength slider has nothing to act on.
  init(name: String, file: TUPresetFile) {
    self.init(
      name: name, steps: file.steps ?? 20, guidanceScale: file.guidanceScale ?? 1, sampler: file.sampler ?? 16,
      shift: file.shift ?? 1, strength: 1, loraFile: file.loraFile ?? "", defaultLoRAWeight: file.loraWeight ?? 1,
      resolutionDependentShift: file.resolutionDependentShift ?? false,
      fixedPrompt: file.prompt.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
  }
}

enum TUPresetTable {
  /// Softness and reach of the mask's edge, in pixels (spec §2).
  static let maskBlur = 30.0
  static let maskOutset = 30

  /// The strength a LoRA can have, as in the app's LoRA card (−4…4).
  static let loraWeightRange: ClosedRange<Double> = -4...4

  static let fluxKlein9BName = "TUP · FLUX.2 klein 9B"
  static let flux3KleinName = "TUP · FLUX.3 klein"
  static let h3ImageName = "TUP · Minimax H3 Image"

  /// MiniMax H3 Image has no LoRA: it regenerates from a reference, so the tile goes to the Moodboard (the switch *Each tile
  /// goes to*) and the prompt names it `<Picture 1>`.
  static let h3ImageModel = "minimax_h3_image_pruned_bf16_i8x.ckpt"
  static let h3ImagePrompt =
    "The entire photograph in <Picture 1>, including its subject, composition, framing, pose, expression, colors, lighting, and background, is <Subject 1>. The target image is a high-resolution, finely detailed rendering of <Subject 1> at a larger size, in the same vertical framing as <Picture 1>."

  /// The restore LoRA of FLUX.3 klein and the prompt of its preset (the trigger phrase of the LoRA, fixed here like the others).
  static let flux3LoRA = "f3_image_klein_restore_lora_f16.ckpt"
  static let flux3Prompt =
    "restore the photo: remove blur, noise and compression artifacts and recover sharp, natural detail, keeping the same composition, people and colors."

  /// The prompt of every tile of FLUX.2 klein 9B. It is fixed here, not the trigger word of the LoRA on the server: that one
  /// says "face", "expression", "figure" and "pose", and on a tile with no face the model adds one. It holds no description
  /// of the content: the tile is all it has to go on.
  static let fluxPrompt =
    "make this photo high-quality. preserve details. preserve overall composition of this photo. Preserve colors and lights."

  /// The detail LoRA of Qwen Image 2.1 and the prompt of its presets (the same for Turbo and the other).
  static let qwenLoRA = "q21_detail_fix_2.0_lora_f16.ckpt"
  static let qwenPrompt =
    "Upscale this image to a substantially higher resolution with a decisive gain in clarity, and add subtle, natural details and textures throughout the frame while keeping the composition, framing, camera viewpoint and zoom exactly as in the input image.  Hold the overall exposure, white balance, saturation, contrast and color grade identical to the input image, preserving  the inherent colors of every object, so the output reads as a cleaner, richer, higher-resolution version of the same image."

  /// The preset for the model in the header: its family (`DTHubContext.family`) and, for Qwen Image 2.1, its file (a Turbo
  /// model has "turbo" in the name and other values); nil when the plug-in does not know it.
  static func preset(forFamily family: String?, model: String? = nil) -> TUPreset? {
    switch family {
    case "flux2_9b":
      return TUPreset(
        name: fluxKlein9BName, steps: 4, guidanceScale: 1, sampler: 16, shift: 3, strength: 1,
        loraFile: "f2_ultra_real_v5_pro_lora_f16.ckpt", defaultLoRAWeight: 1, resolutionDependentShift: false,
        fixedPrompt: fluxPrompt)
    case "flux3_5b":
      return TUPreset(
        name: flux3KleinName, steps: 16, guidanceScale: 1, sampler: 16, shift: 16, strength: 1,
        loraFile: flux3LoRA, defaultLoRAWeight: 1, resolutionDependentShift: false, fixedPrompt: flux3Prompt)
    case "minimax_h3_image":
      return TUPreset(
        name: h3ImageName, steps: 6, guidanceScale: 1, sampler: 10, shift: 3, strength: 1, loraFile: "",
        defaultLoRAWeight: 1, resolutionDependentShift: false, fixedPrompt: h3ImagePrompt, modelFile: h3ImageModel)
    case "qwen_image_2.1":
      guard let model else { return nil }
      if model.lowercased().contains("turbo") {
        return TUPreset(
          name: "TUP · Qwen Image 2.1 Turbo", steps: 8, guidanceScale: 1, sampler: 16, shift: 6.5, strength: 1,
          loraFile: qwenLoRA, defaultLoRAWeight: 2.5, resolutionDependentShift: false, fixedPrompt: qwenPrompt)
      }
      return TUPreset(
        name: "TUP · Qwen Image 2.1", steps: 33, guidanceScale: 1, sampler: 16, shift: 1, strength: 1, loraFile: qwenLoRA,
        defaultLoRAWeight: 2.5, resolutionDependentShift: true, fixedPrompt: qwenPrompt)
    default:
      return nil
    }
  }
}

enum TUPrompt {
  static let sentence = "ALSO PRESERVE COLORS AND LUMINOSITY"

  /// The prompt of the preset, then the user's own instructions (nothing added when they are empty).
  static func compose(_ base: String, extra: String) -> String {
    let added = extra.trimmingCharacters(in: .whitespacesAndNewlines)
    return added.isEmpty ? base : "\(base) \(added)"
  }

  /// The trigger word of the LoRA, then the fixed sentence.
  static func text(trigger: String) -> String {
    let word = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
    return word.isEmpty ? sentence : "\(word) \(sentence)"
  }
}
