import Foundation
import HubKit

/// The "UserComment" of a picture in the layout of Draw Things, so the tools made for Draw Things' pictures read DT
/// Hub's too: `c` (the prompt as sent, trigger words first), `uc`, `seed`, `seed_mode`, `steps`, `sampler` (Draw Things'
/// name), `scale`, `shift`, `size`, `model`, `strength` and `v2` (the configuration as Draw Things writes it). DT Hub's
/// own job, with the seconds the picture took, goes under `dthub`: the others ignore it, DT Hub reads it back.
public enum DrawThingsMetadata {
  @Sendable public static func comment(for job: GenerationJob, elapsed: TimeInterval?) -> String {
    let parameters = job.parameters
    var object: [String: Any] = [
      "c": job.promptWithTriggers,
      "uc": job.negativePrompt,
      "seed": Int(parameters.seed),
      // Draw Things' default, which DT Hub sends too.
      "seed_mode": "Scale Alike",
      "steps": parameters.steps,
      "sampler": parameters.sampler.displayName,
      "scale": parameters.guidanceScale,
      "shift": parameters.shift,
      "size": "\(parameters.width)x\(parameters.height)",
      "model": job.model,
      "strength": job.imageStrength ?? 1,
    ]
    if let mask = job.maskSettings { object["mask_blur"] = mask.blur }
    // The configuration that was sent, seed included (the JSON editor leaves out a random seed; a picture has its own).
    let v2 = (try? JobMapper.configuration(model: job.model, parameters: parameters).toJSON()) ?? "{}"
    if let configuration = try? JSONSerialization.jsonObject(with: Data(v2.utf8)) as? [String: Any] {
      object["v2"] = configuration
    }
    object[GenerationJob.metadataKey] = job.metadataObject(elapsed: elapsed)
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }
}
