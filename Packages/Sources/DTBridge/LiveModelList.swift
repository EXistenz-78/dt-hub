import Foundation
import HubKit

/// One of the lists of models Draw Things publishes, so a model released after this app was built is recognised without
/// waiting for an update. Three lists exist (spec `2026-10-16-selettore-modelli-dt-plus-design.md` §2): Official (the
/// models of the Draw Things app, published by kcjerrell's dt-models), Community (`models.json`, the curated list the
/// app downloads at startup) and Uncurated (`uncurated_models.json`). Each is downloaded once per launch and kept on
/// disk (`CachedDownload`): without the network the saved copy is used, and then the snapshot bundled with DrawThings-Swift.
public actor LiveModelList {
  /// Community: the curated list of the Draw Things app.
  public static let address = URL(string: "https://models.drawthings.ai/models.json")!

  /// Uncurated: with DT+ the cloud has these too.
  public static let uncuratedAddress = URL(string: "https://models.drawthings.ai/uncurated_models.json")!

  /// Official: the models of the Draw Things app (camelCase entries with a `deprecated` flag).
  public static let officialAddress = URL(string: "https://kcjerrell.github.io/dt-models/official_models.json")!

  /// The Community list: ~/Library/Application Support/DT Hub/models-list.json.
  public static let community = LiveModelList(cacheURL: CachedDownload.supportFile("models-list.json"))
  /// The Uncurated list, downloaded only while DT+ is on: …/DT Hub/community-models-list.json (the name kept from
  /// before the lists were named as Draw Things names them, so the copies already saved are still found).
  public static let uncurated = LiveModelList(
    cacheURL: CachedDownload.supportFile("community-models-list.json"), address: LiveModelList.uncuratedAddress)
  /// The Official list, downloaded only while DT+ is on: …/DT Hub/official-models-list.json.
  public static let official = LiveModelList(
    cacheURL: CachedDownload.supportFile("official-models-list.json"), address: LiveModelList.officialAddress,
    parser: LiveModelList.parseOfficial)

  private let source: CachedDownload
  private var parsed: (generation: Int, specs: [String: Data])?

  init(
    cacheURL: URL, address: URL = LiveModelList.address,
    download: @escaping @Sendable (URL) async throws -> Data = CachedDownload.fetch,
    now: @escaping @Sendable () -> Date = { Date() },
    parser: @escaping @Sendable (Data) -> [String: Data] = LiveModelList.parse
  ) {
    self.parser = parser
    source = CachedDownload(
      address: address, cacheURL: cacheURL, isValid: { !parser($0).isEmpty }, download: download, now: now)
  }

  private let parser: @Sendable (Data) -> [String: Data]

  /// The specification of each model of the list, as its JSON object, by file name. Empty when the list was never
  /// downloaded.
  public func specs() async -> [String: Data] {
    guard let data = await source.data() else { return [:] }
    let generation = await source.generation
    if let parsed, parsed.generation == generation { return parsed.specs }
    let specs = parser(data)
    parsed = (generation, specs)
    return specs
  }

  /// A JSON array of specification objects; those without a `file` are skipped.
  static func parse(_ data: Data) -> [String: Data] {
    guard !data.isEmpty, let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [:] }
    var specs: [String: Data] = [:]
    for case let object as [String: Any] in array {
      guard let file = object["file"] as? String, !file.isEmpty, let json = try? JSONSerialization.data(withJSONObject: object)
      else { continue }
      specs[file] = json
    }
    return specs
  }

  /// The Official list: like `parse`, with the keys in snake_case (`defaultScale` → `default_scale`), the way the
  /// other lists and the code that reads a specification have them, and without the `deprecated` flag.
  static func parseOfficial(_ data: Data) -> [String: Data] {
    guard !data.isEmpty, let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [:] }
    var specs: [String: Data] = [:]
    for case let object as [String: Any] in array {
      guard let file = object["file"] as? String, !file.isEmpty else { continue }
      var converted: [String: Any] = [:]
      for (key, value) in object where key != "deprecated" { converted[snakeCased(key)] = value }
      guard let json = try? JSONSerialization.data(withJSONObject: converted) else { continue }
      specs[file] = json
    }
    return specs
  }

  static func snakeCased(_ key: String) -> String {
    var result = ""
    for character in key {
      if character.isUppercase { result += "_" + character.lowercased() } else { result.append(character) }
    }
    return result
  }

  /// The files the Official list marks `"deprecated": true`.
  static func deprecatedFiles(_ data: Data) -> Set<String> {
    guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
    var files: Set<String> = []
    for case let object as [String: Any] in array {
      if object["deprecated"] as? Bool == true, let file = object["file"] as? String, !file.isEmpty { files.insert(file) }
    }
    return files
  }

  /// The deprecated files of the Official list; empty when the list was never downloaded.
  public func deprecated() async -> Set<String> {
    guard let data = await source.data() else { return [] }
    return Self.deprecatedFiles(data)
  }
}
