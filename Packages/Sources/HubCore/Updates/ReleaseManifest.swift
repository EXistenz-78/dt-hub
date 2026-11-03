import Foundation

/// One file of a release the app can fetch: the app itself or a plug-in.
public struct ReleaseItem: Equatable, Sendable {
  /// `"app"` for DT Hub, the bundle identifier for a plug-in.
  public let id: String
  public let name: String
  public let version: String
  /// The name of the zip among the release's assets.
  public let asset: String
  public let sha256: String
  public let size: Int64
  /// The plug-in contract it was made for (nil for the app).
  public let contract: Int?

  public static let appID = "app"

  public init(
    id: String, name: String, version: String, asset: String, sha256: String, size: Int64, contract: Int?
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.asset = asset
    self.sha256 = sha256
    self.size = size
    self.contract = contract
  }
}

/// The `dthub-release.json` that every release carries: the version, the sha256 and the size of each zip.
public struct ReleaseManifest: Equatable, Sendable {
  public static let supportedSchema = 1

  public let tag: String
  public let app: ReleaseItem
  public let plugins: [ReleaseItem]

  public init(tag: String, app: ReleaseItem, plugins: [ReleaseItem]) {
    self.tag = tag
    self.app = app
    self.plugins = plugins
  }

  /// Reads and checks the file; nil when it is not a manifest this app understands (other schema, a missing or
  /// odd field, an asset name that could leave the download folder).
  public static func parse(_ data: Data) -> ReleaseManifest? {
    struct Entry: Decodable {
      let id: String?
      let name: String?
      let version: String
      let asset: String
      let sha256: String
      let size: Int64
      let contract: Int?
    }
    struct File: Decodable {
      let schema: Int
      let tag: String
      let app: Entry
      let plugins: [Entry]
    }
    guard let file = try? JSONDecoder().decode(File.self, from: data), file.schema == supportedSchema,
      !file.tag.isEmpty
    else { return nil }

    func item(_ entry: Entry, id: String, name: String, contract: Int?) -> ReleaseItem? {
      guard !id.isEmpty, !name.isEmpty, !entry.version.isEmpty, entry.size >= 0, isPlainName(entry.asset),
        isSHA256(entry.sha256)
      else { return nil }
      return ReleaseItem(
        id: id, name: name, version: entry.version, asset: entry.asset, sha256: entry.sha256.lowercased(),
        size: entry.size, contract: contract)
    }

    guard let app = item(file.app, id: ReleaseItem.appID, name: "DT Hub", contract: nil) else { return nil }
    var plugins: [ReleaseItem] = []
    for entry in file.plugins {
      guard let id = entry.id, let name = entry.name,
        let plugin = item(entry, id: id, name: name, contract: entry.contract)
      else { return nil }
      plugins.append(plugin)
    }
    return ReleaseManifest(tag: file.tag, app: app, plugins: plugins)
  }

  /// Where the zip of an item is: `<base>/download/<tag>/<asset>`.
  public func downloadURL(for item: ReleaseItem, base: URL) -> URL {
    base.appendingPathComponent("download").appendingPathComponent(tag).appendingPathComponent(item.asset)
  }

  private static func isPlainName(_ name: String) -> Bool {
    !name.isEmpty && name != ".." && name != "." && !name.contains("/") && !name.contains("\\")
  }

  private static func isSHA256(_ text: String) -> Bool {
    text.count == 64 && text.allSatisfy(\.isHexDigit)
  }
}

/// Where the manifest and the files are read from.
public enum UpdateEndpoint {
  public static let releasesBase = URL(string: "https://github.com/EXistenz-78/dt-hub/releases")!
  static let manifestName = "dthub-release.json"

  /// `<base>/latest/download/dthub-release.json`: GitHub sends it to the newest published release, bozze and
  /// prerelease left out. No API, so no rate limit.
  public static func manifestURL(base: URL) -> URL {
    base.appendingPathComponent("latest").appendingPathComponent("download").appendingPathComponent(manifestName)
  }

  /// The real base; `defaults write com.exiztenz.DTHub debug.updateBaseURL <url>` points it at a local folder to try
  /// the whole flow with a test release.
  public static var base: URL {
    UserDefaults.standard.string(forKey: "debug.updateBaseURL").flatMap(URL.init(string:)) ?? releasesBase
  }
}
