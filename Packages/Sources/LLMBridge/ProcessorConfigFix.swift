import Foundation

/// Models converted with a recent Transformers keep the image settings of their processor in `processor_config.json`,
/// under `image_processor`; mlx-swift-lm reads them at the top level, as the older `preprocessor_config.json` has them.
/// Without a `preprocessor_config.json` the vision part fails to load and the library quietly falls back to the text-only
/// model, which drops every picture. This adds the missing file next to the weights (an addition: nothing is changed).
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

  /// Writes `preprocessor_config.json` when the folder lacks it and has a nested `processor_config.json`. True when it
  /// wrote the file; false when there was nothing to do, or the folder cannot be written (the caller goes on: the
  /// model then loads without its vision part and says so when it is asked about a picture).
  @discardableResult
  static func addFlatFileIfNeeded(in folder: URL) -> Bool {
    let fileManager = FileManager.default
    let flatURL = folder.appendingPathComponent(flatFileName)
    guard !fileManager.fileExists(atPath: flatURL.path),
      let nested = try? Data(contentsOf: folder.appendingPathComponent(nestedFileName)),
      let flat = flattened(nested)
    else { return false }
    do {
      try flat.write(to: flatURL, options: .atomic)
      return true
    } catch {
      return false
    }
  }
}
