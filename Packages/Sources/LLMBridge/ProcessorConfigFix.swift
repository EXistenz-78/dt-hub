import Foundation

/// Models converted with a recent Transformers keep the image settings of their processor in `processor_config.json`,
/// under `image_processor`; mlx-swift-lm reads them at the top level, as the older `preprocessor_config.json` has them.
/// Without a `preprocessor_config.json` the vision part fails to load and the library quietly falls back to the text-only
/// model, which drops every picture. This adds the missing file, or the missing `processor_class` key, next to the weights.
enum ProcessorConfigFix {
  static let flatFileName = "preprocessor_config.json"
  static let nestedFileName = "processor_config.json"

  /// The flat layout of a nested `processor_config.json`; nil when it has no `image_processor` object.
  static func flattened(_ nested: Data) -> Data? {
    guard let object = (try? JSONSerialization.jsonObject(with: nested)) as? [String: Any],
      var flat = object["image_processor"] as? [String: Any]
    else { return nil }
    let maxPixels = flat.removeValue(forKey: "max_pixels")
    let minPixels = flat.removeValue(forKey: "min_pixels")
    if flat["size"] == nil {
      var size: [String: Any] = [:]
      if let maxPixels { size["longest_edge"] = maxPixels }
      if let minPixels { size["shortest_edge"] = minPixels }
      if !size.isEmpty { flat["size"] = size }
    }
    if let processorClass = object["processor_class"] as? String { flat["processor_class"] = processorClass }
    return try? JSONSerialization.data(withJSONObject: flat, options: [.prettyPrinted, .sortedKeys])
  }

  static let backupFileName = "preprocessor_config.json.orig"

  /// Fixes the flat `preprocessor_config.json` next to the weights when the folder has a nested `processor_config.json`.
  /// Two cases, both additions:
  /// - the flat file is missing: it is written from the nested one;
  /// - the flat file exists but has no `processor_class` (mlx-swift-lm then refuses to load the vision part) while the
  ///   nested one names it: only that key is added, after the file as it was has been copied to
  ///   `preprocessor_config.json.orig` (an existing copy is kept).
  /// True when it wrote the file; false when there was nothing to do, or the folder cannot be written (the caller goes
  /// on: the model then loads without its vision part and says so when it is asked about a picture).
  @discardableResult
  static func addFlatFileIfNeeded(in folder: URL) -> Bool {
    let fileManager = FileManager.default
    let flatURL = folder.appendingPathComponent(flatFileName)
    guard let nested = try? Data(contentsOf: folder.appendingPathComponent(nestedFileName)) else { return false }
    if !fileManager.fileExists(atPath: flatURL.path) {
      guard let flat = flattened(nested) else { return false }
      return (try? flat.write(to: flatURL, options: .atomic)) != nil
    }
    guard let existing = try? Data(contentsOf: flatURL),
      var flat = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any],
      flat["processor_class"] == nil,
      let object = (try? JSONSerialization.jsonObject(with: nested)) as? [String: Any],
      let processorClass = object["processor_class"] as? String
    else { return false }
    flat["processor_class"] = processorClass
    guard let updated = try? JSONSerialization.data(withJSONObject: flat, options: [.prettyPrinted, .sortedKeys])
    else { return false }
    let backupURL = folder.appendingPathComponent(backupFileName)
    do {
      if !fileManager.fileExists(atPath: backupURL.path) { try existing.write(to: backupURL, options: .atomic) }
      try updated.write(to: flatURL, options: .atomic)
      return true
    } catch {
      return false
    }
  }
}
