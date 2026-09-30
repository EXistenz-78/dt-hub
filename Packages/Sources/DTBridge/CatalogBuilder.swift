import Foundation
import HubKit

/// Name and family of a model file, read from its Draw Things model specification.
struct ModelSpecInfo: Equatable, Sendable {
  let name: String
  let family: String?
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
        modelSpecs[file].map { CatalogModel(file: file, name: $0.name, family: $0.family) }
      }
    let unlistedLoRAs = files
      .filter { $0.contains("_lora_") && !loraFiles.contains($0) && modelSpecs[$0] == nil }
      .map { CatalogLoRA(file: $0, name: $0, family: nil) }

    return ModelCatalog(models: models, loras: loraEntries + unlistedLoRAs, fileCount: files.count)
  }

  /// The server's LoRA metadata: a JSON array of objects with `file`, `name`, `version`.
  /// Unreadable data or entries without `file` are skipped, never fatal.
  static func parseLoRAMetadata(_ data: Data) -> [CatalogLoRA] {
    guard !data.isEmpty,
      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    return array.compactMap { entry in
      guard let file = entry["file"] as? String else { return nil }
      return CatalogLoRA(
        file: file, name: entry["name"] as? String ?? file, family: entry["version"] as? String)
    }
  }

  /// Name and family from a spec's JSON object; the file name stands in for a missing name.
  static func specInfo(json: Data, file: String) -> ModelSpecInfo {
    let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
    return ModelSpecInfo(name: object["name"] as? String ?? file, family: object["version"] as? String)
  }
}
