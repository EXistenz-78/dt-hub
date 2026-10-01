import Foundation
import HubKit

/// Finds the language models in a folder (spec §9). A model is a folder with a `config.json`
/// and at least one `.safetensors` file, up to two levels below the models folder (the layout
/// of Hugging Face downloads and of LM Studio, `publisher/model`).
public enum LanguageModelScanner {
  public static let maxDepth = 2

  public static func models(in folder: URL, fileManager: FileManager = .default) -> [LanguageModelDescriptor] {
    var found: [LanguageModelDescriptor] = []
    scan(folder, root: folder, depth: 0, fileManager: fileManager, into: &found)
    return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static func scan(
    _ directory: URL, root: URL, depth: Int, fileManager: FileManager, into found: inout [LanguageModelDescriptor]
  ) {
    let entries =
      (try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
        options: [.skipsHiddenFiles])) ?? []
    if depth > 0, let model = descriptor(of: directory, entries: entries, root: root) {
      found.append(model)
      return
    }
    guard depth < maxDepth else { return }
    for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      scan(entry, root: root, depth: depth + 1, fileManager: fileManager, into: &found)
    }
  }

  private static func descriptor(of directory: URL, entries: [URL], root: URL) -> LanguageModelDescriptor? {
    let names = Set(entries.map(\.lastPathComponent))
    guard names.contains("config.json"), names.contains(where: { $0.hasSuffix(".safetensors") }) else { return nil }
    let size = entries.reduce(Int64(0)) { total, file in
      total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    let prefix = root.standardizedFileURL.path + "/"
    let path = directory.standardizedFileURL.path
    let name = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : directory.lastPathComponent
    return LanguageModelDescriptor(
      path: path, name: name, sizeBytes: size, supportsImages: hasVision(entries.first { $0.lastPathComponent == "config.json" }))
  }

  /// A vision-language model's `config.json` has a `vision_config` section.
  private static func hasVision(_ config: URL?) -> Bool {
    guard let config, let data = try? Data(contentsOf: config),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return object["vision_config"] != nil
  }
}
