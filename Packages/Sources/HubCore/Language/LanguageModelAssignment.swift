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

/// Keeps the assignments of Settings › LLM coherent when the list of installed LLMs changes (pure logic).
public enum LanguageModelAssignments {
  /// 1. Migration: the old chosen model (`selectedModel`) is present → it becomes "all others · both" and any other
  ///    LLM on "all others" goes to "none" (the manager then clears `selectedModel`, so this runs once per choice).
  /// 2. A single installed LLM with no entry (or none) and nobody on "all others" → "all others · both".
  /// 3. The model just downloaded does the same when nobody is on "all others".
  /// 4. Every installed LLM without an entry gets "none · both". Entries of absent LLMs are kept.
  public static func reconciled(
    _ settings: LanguageModelSettings, models: [LanguageModelDescriptor], downloaded: String? = nil
  ) -> [String: LanguageModelAssignment] {
    var result = settings.assignments
    let allBoth = LanguageModelAssignment(family: .allOthers, use: .both)
    func nobodyOnAllOthers() -> Bool { !result.values.contains { $0.family == .allOthers } }
    func isFree(_ name: String) -> Bool { result[name] == nil || result[name]?.family == LanguageModelFamily.none }

    if let chosen = models.first(where: { $0.path == settings.selectedModel }) {
      for (name, entry) in result where entry.family == .allOthers && name != chosen.name {
        result[name] = LanguageModelAssignment(family: .none, use: .both)
      }
      result[chosen.name] = allBoth
    }
    if models.count == 1, let only = models.first, isFree(only.name), nobodyOnAllOthers() {
      result[only.name] = allBoth
    }
    if let downloaded, models.contains(where: { $0.name == downloaded }), isFree(downloaded), nobodyOnAllOthers() {
      result[downloaded] = allBoth
    }
    for model in models where result[model.name] == nil {
      result[model.name] = LanguageModelAssignment(family: .none, use: .both)
    }
    return result
  }
}
