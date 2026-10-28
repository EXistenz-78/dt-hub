import Foundation

typealias PFPresetSender = @MainActor ([[String: Any]]) async -> [String: Any]?

/// The two presets the plug-in puts in the Preset menu (the app never touches one that is already there). The values are those of the user's own presets.
/// The presets carry no prompt: the plug-in sends it for each pass, and DT Hub puts the LoRA's trigger word in front.
enum PFPresets {
  static let panoName = "PANO F3"
  static let seamName = "PANO F3 Seamfix"
  static let model = "flux_3_klein_q8p.ckpt"
  static let panoLoRA = "f3_360_lora_f16.ckpt"
  static let panoTrigger = "create a 360 hdr"
  static let seamLoRA = "f3_seamfix_lora_f16.ckpt"
  static let seamTrigger = "seamfix"

  /// The LoRA of a pass, as `loras` takes it: file, weight 1, mode 0 and its trigger word.
  static func lora(seam: Bool) -> [String: Any] {
    ["file": seam ? seamLoRA : panoLoRA, "weight": 1.0, "mode": 0, "trigger": seam ? seamTrigger : panoTrigger]
  }

  /// The `presets` message's entries: the panorama preset, then the Seamfix one.
  static func messages() -> [[String: Any]] {
    func preset(name: String, seam: Bool) -> [String: Any] {
      [
        "name": name, "model": model,
        "fields": [
          "steps": 16, "guidanceScale": 1.0, "sampler": 16, "shift": 16.0, "resolutionDependentShift": false, "highRes": true,
        ] as [String: Any],
        "loras": [lora(seam: seam)],
      ]
    }
    return [preset(name: panoName, seam: false), preset(name: seamName, seam: true)]
  }

  /// Sends both presets; the app answers how many were added (a name already in the menu is left alone).
  @MainActor
  static func register(using send: PFPresetSender) async -> [String: Any]? { await send(messages()) }
}
