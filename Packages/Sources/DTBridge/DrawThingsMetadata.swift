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

  /// The PNG "Description" in the layout of Draw Things (which ImageIO mirrors into the XMP `dc:description`, shown
  /// as IPTC): the prompt as sent, then the negative prompt on a line of its own after a "-" (left out when empty),
  /// then one line of parameters; DTInspector reads the parameters from here. Decimals keep their ".0" as in
  /// Draw Things.
  @Sendable public static func description(for job: GenerationJob) -> String {
    let parameters = job.parameters
    var fields = [
      "Steps: \(parameters.steps)",
      "Sampler: \(parameters.sampler.displayName)",
      "Guidance Scale: \(parameters.guidanceScale)",
      "Seed: \(parameters.seed)",
      "Size: \(parameters.width)x\(parameters.height)",
      "Model: \(job.model)",
      "Strength: \(job.imageStrength ?? 1)",
      "Seed Mode: Scale Alike",
      "Shift: \(parameters.shift)",
    ]
    for lora in parameters.loras {
      fields.append("LoRA Model: \(lora.file)")
      fields.append("LoRA Weight: \(lora.weight)")
    }
    var lines = [job.promptWithTriggers]
    if !job.negativePrompt.isEmpty { lines.append("-" + job.negativePrompt) }
    lines.append(fields.joined(separator: ", "))
    return lines.joined(separator: "\n")
  }
}
