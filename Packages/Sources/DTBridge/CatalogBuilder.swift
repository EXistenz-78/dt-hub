import Foundation
import HubKit

/// Name, family and capabilities of a model file, read from its Draw Things model specification.
struct ModelSpecInfo: Equatable, Sendable {
  let name: String
  let family: String?
  var capabilities: ModelCapabilities = .unknown
}

/// Turns what the server's echo reports into a `ModelCatalog` (spec §5).
///
/// A file is a model when a model specification describes it: the specs bundled with
/// DrawThings-Swift cover the official models, the server's own cover the imported ones.
/// Every other file (text encoders, VAEs, ControlNets, upscalers…) is not a model.
/// LoRAs come from the server's LoRA metadata; a file named `…_lora_…` without metadata
/// is still listed, with no family.
enum CatalogBuilder {
  static func build(files: [String], modelSpecs: [String: ModelSpecInfo], loraMetadata: Data) -> ModelCatalog {
    let installed = Set(files)
    let loraEntries = parseLoRAMetadata(loraMetadata).filter { installed.contains($0.file) }
    let loraFiles = Set(loraEntries.map(\.file))

    let models = files
      .filter { !loraFiles.contains($0) }
      .compactMap { file in
        modelSpecs[file].map {
          CatalogModel(file: file, name: $0.name, family: $0.family, capabilities: $0.capabilities)
        }
      }
    let others = files.filter { !loraFiles.contains($0) && modelSpecs[$0] == nil }
    let unlistedLoRAs = files
      .filter { $0.contains("_lora_") && !loraFiles.contains($0) && modelSpecs[$0] == nil }
      .map { CatalogLoRA(file: $0, name: $0, family: nil) }

    return ModelCatalog(
      models: models, loras: loraEntries + unlistedLoRAs, fileCount: files.count,
      upscalers: others.filter(isUpscaler).sorted(), faceRestorers: others.filter(isFaceRestorer).sorted())
  }

  /// Upscalers of Draw Things' zoo (Real-ESRGAN, UltraSharp, Remacri, NMKD…), by file name.
  static func isUpscaler(_ file: String) -> Bool {
    let name = file.lowercased()
    // Latent upscalers (e.g. LTX's spatial upscaler) are helpers of a model, not image upscalers.
    guard !name.contains("_lora_"), !name.contains("latent"), !name.contains("spatial") else { return false }
    return ["esrgan", "upscal", "ultrasharp", "remacri", "superscale", "4x_", "2x_"].contains { name.contains($0) }
  }

  /// Face restorers of Draw Things' zoo (RestoreFormer, CodeFormer, GFPGAN), by file name;
  /// ParseNet is their helper, not a choice.
  static func isFaceRestorer(_ file: String) -> Bool {
    let name = file.lowercased()
    return ["restoreformer", "codeformer", "gfpgan"].contains { name.contains($0) }
  }

  /// The server's LoRA metadata: a JSON array of objects with `file`, `name`, `version`,
  /// `prefix` (the trigger word) and, for some, `weight`.
  /// Unreadable data or entries without `file` are skipped, never fatal.
  static func parseLoRAMetadata(_ data: Data) -> [CatalogLoRA] {
    guard !data.isEmpty,
      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    return array.compactMap { entry in
      guard let file = entry["file"] as? String else { return nil }
      return CatalogLoRA(
        file: file, name: entry["name"] as? String ?? file, family: entry["version"] as? String,
        trigger: (entry["prefix"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
        defaultWeight: (entry["weight"] as? NSNumber)?.doubleValue)
    }
  }

  /// Name, family and capabilities from a spec's JSON object; the file name stands in for a
  /// missing name.
  static func specInfo(json: Data, file: String) -> ModelSpecInfo {
    let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
    return ModelSpecInfo(
      name: object["name"] as? String ?? file, family: object["version"] as? String,
      capabilities: capabilities(object))
  }

  /// What the spec says the model supports: guidance embed, TeaCache coefficients, its text
  /// encoders (CLIP-L, OpenCLIP-G, T5) and its native size (`default_scale` × 64).
  static func capabilities(_ spec: [String: Any]) -> ModelCapabilities {
    let textEncoder = spec["text_encoder"] as? String ?? ""
    let encoders = [textEncoder, spec["clip_encoder"] as? String ?? "", spec["t5_encoder"] as? String ?? ""]
      + (spec["additional_clip_encoders"] as? [String] ?? [])
    func has(_ fragment: String) -> Bool { encoders.contains { $0.contains(fragment) } }
    return ModelCapabilities(
      guidanceEmbed: spec["guidance_embed"] as? Bool ?? false,
      teaCache: spec["tea_cache_coefficients"] != nil,
      clipL: has("clip_vit_l14"),
      openClipG: has("open_clip_vit_bigg14"),
      t5: has("t5_xxl"),
      optionalT5: spec["t5_encoder"] != nil,
      clipSkip: textEncoder.contains("clip_vit") || textEncoder.contains("open_clip"),
      nativeSize: (spec["default_scale"] as? Int).map { $0 * 64 })
  }
}
