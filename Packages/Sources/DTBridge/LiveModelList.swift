import Foundation
import HubKit

/// The list of official models Draw Things publishes (the one its app downloads at startup), so a model released
/// after this app was built is recognised without waiting for an update. Downloaded once per launch and kept on disk
/// (`CachedDownload`): without the network the saved copy is used, and then the snapshot bundled with DrawThings-Swift.
public actor LiveModelList {
  public static let address = URL(string: "https://models.drawthings.ai/models.json")!

  /// The list of the app: ~/Library/Application Support/DT Hub/models-list.json.
  public static let shared = LiveModelList(cacheURL: CachedDownload.supportFile("models-list.json"))

  private let source: CachedDownload
  private var parsed: (generation: Int, specs: [String: Data])?

  init(
    cacheURL: URL, address: URL = LiveModelList.address,
    download: @escaping @Sendable (URL) async throws -> Data = CachedDownload.fetch,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    source = CachedDownload(
      address: address, cacheURL: cacheURL, isValid: { !Self.parse($0).isEmpty }, download: download, now: now)
  }

  /// The specification of each model of the list, as its JSON object, by file name. Empty when the list was never
  /// downloaded.
  public func specs() async -> [String: Data] {
    guard let data = await source.data() else { return [:] }
    let generation = await source.generation
    if let parsed, parsed.generation == generation { return parsed.specs }
    let specs = Self.parse(data)
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
}
