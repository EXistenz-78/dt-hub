import Foundation

/// The JSON the plug-in sends to DT Hub: its two presets and what "Send" contributes. Pure, so it can be tested.
enum SLRMessages {
  /// The prefix of the names of the plug-in's presets: the Preset menu shows nothing else about where one comes from.
  static let acronym = "SLR"
  static let overcastName = "\(acronym) · Overcast"
  static let matchName = "\(acronym) · Match the sun"
  static let overcastPrompt = "make it an overcast day, remove the shadows"
  static let matchPrompt = "match light direction, colors and intensity from the reference image 2"
  static let lora = "flux_2_sun_direction_lora_v1_lora_f16.ckpt"
  static let loraWeight = 0.6
  /// The name of the sphere in the Moodboard.
  static let sphereName = "Sphere light"
  static let pipelineName = "Sphere Light"

  /// The settings of the sun-direction passes of the Light Direction companion script.
  static func fields(prompt: String) -> [String: Any] {
    [
      "prompt": prompt, "steps": 4, "guidanceScale": 1.0, "shift": 3, "sampler": 16,
      "batchSize": 1, "batchCount": 1, "cfgZeroStar": false,
      // A preset leaves this switch on unless it says otherwise, and with it on Draw Things ignores the shift.
      "resolutionDependentShift": false,
    ]
  }

  /// The two presets for the Preset menu (`presets` message). The app never overwrites a name it has.
  static func presets() -> [[String: Any]] {
    [
      ["name": overcastName, "fields": fields(prompt: overcastPrompt)],
      [
        "name": matchName, "fields": fields(prompt: matchPrompt),
        "loras": [["file": lora, "weight": loraWeight]],
      ],
    ]
  }

  static func moodboard(spherePath: String) -> [[String: Any]] {
    [["name": sphereName, "path": spherePath]]
  }

  /// The `pipeline` of a `contribute`: with `overcast` a first pass flattens the shadows of the canvas, then the
  /// sun is matched starting from that picture; without it only the second pass runs, on the canvas.
  static func pipeline(overcast: Bool, spherePath: String) -> [String: Any] {
    var steps: [[String: Any]] = []
    if overcast { steps.append(["title": "Overcast", "preset": overcastName]) }
    steps.append([
      "title": "Match the sun", "preset": matchName, "moodboard": moodboard(spherePath: spherePath),
      "useOutputAsStart": overcast,
    ])
    return ["name": pipelineName, "steps": steps]
  }
}
