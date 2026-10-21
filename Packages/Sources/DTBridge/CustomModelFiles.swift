import Foundation

/// Where the specifications of the imported models can be read from.
public struct CustomModelSource: Sendable {
  /// The `custom.json` of the models folder of the server (the user's own folder: read freely).
  public var folderFile: URL?
  /// The `custom.json` of the Draw Things app, in the app's private folder: macOS asks the user before another app reads
  /// it, so it is read only for a file nothing else describes, and what it says is kept in `cacheFile`.
  public var appFile: URL
  /// DT Hub's own copy of what was read from `appFile`, and the files that were looked up there.
  public var cacheFile: URL

  public init(folderFile: URL?, appFile: URL, cacheFile: URL) {
    self.folderFile = folderFile
    self.appFile = appFile
    self.cacheFile = cacheFile
  }
}

/// The `custom.json` of Draw Things: the models the user imported, one specification each. The Draw Things app sends
/// them with its echo; the gRPCServerCLI does not, so DT Hub reads the files itself.
enum CustomModelFiles {
  /// The specification of each model of a file, by its file name; nil when the file is missing or is not a list.
  static func read(_ url: URL) -> [String: Data]? {
    guard let data = try? Data(contentsOf: url),
      let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else { return nil }
    var result: [String: Data] = [:]
    for entry in list {
      guard let file = entry["file"] as? String, !file.isEmpty, result[file] == nil,
        let json = try? JSONSerialization.data(withJSONObject: entry)
      else { continue }
      result[file] = json
    }
    return result
  }

  /// The specification of each model of the files, by its file name; the first file that has a model wins. A file that
  /// is missing, unreadable or not a list is skipped.
  static func specs(in urls: [URL]) -> [String: Data] {
    var result: [String: Data] = [:]
    for url in urls {
      for (file, json) in read(url) ?? [:] where result[file] == nil { result[file] = json }
    }
    return result
  }

  private struct Cache: Codable {
    var checked: Set<String> = []
    var models: [String: String] = [:]
  }

  /// The specifications of the server's `files` that nothing described (`described` are the ones that were): from the
  /// models folder's `custom.json`, from the cache, and, for a file never looked up, from the Draw Things app's, whose
  /// answer is kept. The app's file is opened only for such a file: that is when macOS asks for permission, once per
  /// new model instead of at every launch. A file that cannot be read marks nothing as looked up.
  static func specs(for files: [String], described: Set<String>, source: CustomModelSource) -> [String: Data] {
    let undescribed = files.filter { !described.contains($0) }
    guard !undescribed.isEmpty else { return [:] }
    var cache = (try? Data(contentsOf: source.cacheFile)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) } ?? Cache()
    var found = source.folderFile.map { read($0) ?? [:] } ?? [:]
    for (file, json) in cache.models where found[file] == nil { found[file] = Data(json.utf8) }
    let unknown = undescribed.filter { found[$0] == nil && !cache.checked.contains($0) }
    if !unknown.isEmpty, let app = read(source.appFile) {
      for file in unknown {
        if let json = app[file] {
          found[file] = json
          cache.models[file] = String(decoding: json, as: UTF8.self)
        }
        cache.checked.insert(file)
      }
      try? FileManager.default.createDirectory(at: source.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? JSONEncoder().encode(cache).write(to: source.cacheFile, options: .atomic)
    }
    return found.filter { undescribed.contains($0.key) }
  }
}
