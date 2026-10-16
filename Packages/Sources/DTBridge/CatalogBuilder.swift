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

  /// The catalog with the models of Draw Things' lists (Official, Community, Uncurated) that are not in the server's folder,
  /// marked as remote: with DT+ (Bridge Mode) the cloud runs them. Nothing else changes.
  static func addingRemoteModels(
    to catalog: ModelCatalog, live: [String: Data], sources: [String: ModelSource] = [:]
  ) -> ModelCatalog {
    let installed = Set(catalog.models.map(\.file))
    let remote = live.keys.sorted().filter { !installed.contains($0) }.compactMap { file -> CatalogModel? in
      guard let json = live[file] else { return nil }
      let info = specInfo(json: json, file: file)
      return CatalogModel(
        file: file, name: info.name, family: info.family, capabilities: info.capabilities, isRemote: true,
        source: sources[file])
    }
    guard !remote.isEmpty || !sources.isEmpty else { return catalog }
    // The installed models that are in a list say so too.
    let local = catalog.models.map { model in
      sources[model.file].map { model.with(source: $0, isRemote: model.isRemote) } ?? model
    }
    return ModelCatalog(
      models: local + remote, loras: catalog.loras, fileCount: catalog.fileCount, upscalers: catalog.upscalers,
      faceRestorers: catalog.faceRestorers)
  }

  /// The list a file comes from: Official, then Community, then Uncurated (the first one that has it).
  static func sources(
    official: [String: Data], community: [String: Data], uncurated: [String: Data]
  ) -> [String: ModelSource] {
    var result: [String: ModelSource] = [:]
    for file in uncurated.keys { result[file] = .uncurated }
    for file in community.keys { result[file] = .community }
    for file in official.keys { result[file] = .official }
    return result
  }

  /// The catalog while DT+ is on and the cloud's list is known: the models are only those the cloud has (the installed
  /// ones keep the server's description, the others come from `specs` and are marked as remote), minus a deprecated
  /// Official model that is not installed. Each model carries the list it comes from (`sources`); an installed one that
  /// no list has stays in the catalog with no source: the picker does not show it (spec §2) but, if it is the chosen
  /// one, RUN still finds it. The
  /// LoRAs are the local ones plus the cloud's (`cloudLoRAs`, from Draw Things' `loras.json`, or by name when it does
  /// not list them). The LoRA card keeps showing only the family of the current model.
  static func cloudCatalog(
    local: ModelCatalog, specs: [String: Data], sources: [String: ModelSource], deprecated: Set<String>,
    cloudFiles: Set<String>, cloudLoRAs: [CatalogLoRA]
  ) -> ModelCatalog {
    let localModels = local.models.compactMap { model -> CatalogModel? in
      guard cloudFiles.contains(model.file) else { return nil }
      return model.with(source: sources[model.file], isRemote: false)
    }
    let localFiles = Set(local.models.map(\.file))
    let remote = specs.keys.sorted().filter {
      cloudFiles.contains($0) && !localFiles.contains($0) && !deprecated.contains($0)
    }.compactMap { file -> CatalogModel? in
      guard let json = specs[file] else { return nil }
      let info = specInfo(json: json, file: file)
      return CatalogModel(
        file: file, name: info.name, family: info.family, capabilities: info.capabilities, isRemote: true,
        source: sources[file])
    }

    var known = Set(local.loras.map(\.file))
    var loras = local.loras
    let described = Dictionary(cloudLoRAs.map { ($0.file, $0) }) { first, _ in first }
    for file in cloudFiles.sorted() where file.contains("_lora") && !known.contains(file) {
      known.insert(file)
      loras.append(described[file] ?? CatalogLoRA(file: file, name: file, family: inferredFamily(ofLoRA: file)))
    }
    return ModelCatalog(
      models: localModels + remote, loras: loras, fileCount: local.fileCount, upscalers: local.upscalers,
      faceRestorers: local.faceRestorers)
  }

  /// The family of a cloud LoRA that `loras.json` does not list (old speed-ups of SD 1.5, SDXL, SD3, LTX, Wan), from
  /// its file name; nil when the name does not say (it then shows for every model, as an unknown one).
  static func inferredFamily(ofLoRA file: String) -> String? {
    let name = file.lowercased()
    if name.contains("refiner") { return nil }
    if name.contains("sd3") { return "sd3" }
    if name.contains("ltx_2.3") { return "ltx2.3" }
    if name.contains("wan_2.1_14b") { return "wan_v2.1_14b" }
    if name.contains("wan_2.1_1.3b") { return "wan_v2.1_1.3b" }
    if name.contains("sdxl") || name.contains("_xl_") || name.contains("fooocus") { return "sdxl_base_v0.9" }
    if name.contains("sd_v1") || name.contains("v1.5") { return "v1" }
    return nil
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
      nativeSize: (spec["default_scale"] as? Int).map { $0 * 64 },
      modifier: spec["modifier"] as? String)
  }
}
