import Foundation

typealias PSPresetSender = @MainActor ([[String: Any]]) async -> [String: Any]?
typealias PSContribute = @MainActor ([String: Any]) async -> [String: Any]?

/// The presets the plug-in puts in the Preset menu (the app never touches one that is already there, so the user may change them: another
/// model, the 4B LoRA, other quantisations). Normal runs the base model alone, Fast adds the KV refiner. The values are those of the preset the
/// user made and tried (30 steps for Normal, 16 for Fast).
enum PSPresets {
  static let normalName = "PAN · 360 ERP"
  static let fastName = "PAN · 360 ERP Fast"
  /// The preset of the seam correction: the KV model alone, 4 steps, no LoRA, and the prompt that makes the junction disappear.
  static let seamlessName = "PAN · 360 Seamless"
  static let seamlessPrompt =
    "recreate the central part of the image to make the vertical junction seamless, correct the background elements to avoid mismatches, visible junctions and distortions."

  static let model = "flux_2_klein_base_9b_i8x.ckpt"
  static let refiner = "flux_2_klein_9b_kv_i8x.ckpt"
  static let loraFile = "f2_360_erp_outpaint_lora_v1_lora_f16.ckpt"
  /// The LoRA's trigger phrase: DT Hub puts it in front of the prompt at RUN, so the plug-in never writes it in the prompt.
  static let trigger =
    "fill the green spaces according to the image. outpaint as a seamless 360 equirectangular panorama (2:1). keep the horizon level. match left and right edges."

  /// The `presets` message's entries: Normal, Fast, then Seamless.
  static func messages() -> [[String: Any]] {
    func preset(name: String, steps: Int) -> [String: Any] {
      [
        "name": name, "model": model,
        "fields": ["steps": steps, "guidanceScale": 4.0, "sampler": 16, "shift": 3.0, "resolutionDependentShift": true] as [String: Any],
        "loras": [["file": loraFile, "weight": 1.0, "mode": 0, "trigger": trigger] as [String: Any]],
      ]
    }
    // Normal runs the base model alone for 30 steps; Fast hands over to the KV refiner and needs only 16.
    let normal = preset(name: normalName, steps: 30)
    var fast = preset(name: fastName, steps: 16)
    fast["advanced"] = ["refinerModel": refiner, "refinerStart": 0.25] as [String: Any]
    let seamless: [String: Any] = [
      "name": seamlessName, "model": refiner,
      "fields": [
        "steps": 4, "guidanceScale": 1.0, "sampler": 16, "shift": 3.0, "resolutionDependentShift": false, "prompt": seamlessPrompt,
      ] as [String: Any],
      "loras": [[String: Any]](),
    ]
    return [normal, fast, seamless]
  }

  /// Sends both presets; the app answers how many were added (a name already in the menu is left alone).
  @MainActor
  static func register(using send: PSPresetSender) async -> [String: Any]? { await send(messages()) }
}
