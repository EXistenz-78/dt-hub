import Foundation

/// The plug-in contract between the app and a downloaded plug-in bundle (spec: plug-in design §3).
public enum PluginContract {
  /// The contract versions this app understands. A plug-in made for another one is refused.
  public static let supported: Set<Int> = [1]
  public static let current = 1
  /// The `Info.plist` key that holds the contract version a plug-in was made for.
  public static let infoKey = "DTHubContract"
  /// The folder extension of a plug-in bundle.
  public static let bundleExtension = "dthubplugin"
}

/// What a plug-in says about itself (the JSON its `dthubManifest` returns).
public struct PluginManifest: Codable, Equatable, Sendable {
  /// The bundle identifier.
  public var id: String
  public var name: String
  public var version: String
  public var contract: Int
  /// An SF Symbol name for the tab.
  public var symbol: String
  /// Model families it works with; nil or empty = all.
  public var families: [String]?

  public init(
    id: String, name: String, version: String = "0", contract: Int = PluginContract.current,
    symbol: String = "puzzlepiece.extension", families: [String]? = nil
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.contract = contract
    self.symbol = symbol
    self.families = families
  }

  /// Lenient: only the identifier, the name and the contract version are needed.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    contract = try container.decode(Int.self, forKey: .contract)
    version = (try? container.decodeIfPresent(String.self, forKey: .version)) ?? "0"
    symbol = (try? container.decodeIfPresent(String.self, forKey: .symbol)) ?? "puzzlepiece.extension"
    families = try? container.decodeIfPresent([String].self, forKey: .families)
  }

  /// Whether it works with a model family (nil = unknown family: everything applies).
  public func supports(family: String?) -> Bool {
    guard let family, let families, !families.isEmpty else { return true }
    return families.contains(family)
  }
}

/// A dotted version ("1.2.10") compared number by number.
public struct PluginVersion: Comparable, Equatable, Sendable {
  public let parts: [Int]

  public init(_ text: String) {
    parts = text.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
  }

  public static func < (lhs: PluginVersion, rhs: PluginVersion) -> Bool {
    let count = max(lhs.parts.count, rhs.parts.count)
    for index in 0..<count {
      let a = index < lhs.parts.count ? lhs.parts[index] : 0
      let b = index < rhs.parts.count ? rhs.parts[index] : 0
      if a != b { return a < b }
    }
    return false
  }

  public static func == (lhs: PluginVersion, rhs: PluginVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}
