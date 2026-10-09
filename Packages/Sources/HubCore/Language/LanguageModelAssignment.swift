import Foundation
import HubKit

/// The family of image models an LLM is assigned to in Settings › LLM.
/// Encoded as one string: "" = none, "*" = all others, anything else is the family key.
public enum LanguageModelFamily: Hashable, Codable, Sendable {
  /// Not used by the prompt buttons (still visible to plug-ins).
  case none
  /// Serves every family that has no LLM of its own.
  case allOthers
  /// A Draw Things `version` key, e.g. "qwen_image_2.1".
  case family(String)

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    switch text {
    case "": self = .none
    case "*": self = .allOthers
    default: self = .family(text)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .none: try container.encode("")
    case .allOthers: try container.encode("*")
    case .family(let key): try container.encode(key)
    }
  }
}

/// What an assigned LLM is used for.
public enum LanguageModelUse: String, Codable, Sendable, CaseIterable {
  case enhance, describe, both, pluginsOnly

  public func covers(_ task: LanguageModelTask) -> Bool {
    switch (self, task) {
    case (.both, _), (.enhance, .enhance), (.describe, .describe): true
    default: false
    }
  }
}

public struct LanguageModelAssignment: Equatable, Codable, Sendable {
  public var family: LanguageModelFamily
  public var use: LanguageModelUse

  public init(family: LanguageModelFamily, use: LanguageModelUse) {
    self.family = family
    self.use = use
  }
}
