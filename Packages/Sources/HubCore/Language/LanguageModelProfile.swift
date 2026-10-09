import Foundation
import HubKit

/// What an LLM's own folder says about how to use it: its system prompt and sampling values.
/// Unreadable, empty or broken files count as missing.
public struct LanguageModelProfile: Equatable, Sendable {
  public struct Generation: Equatable, Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?

    public init(temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil) {
      self.temperature = temperature
      self.topP = topP
      self.topK = topK
    }
  }

  public var generation: Generation?
  private var enhancePrompt: String?
  private var describePrompt: String?

  public init(generation: Generation? = nil, enhancePrompt: String? = nil, describePrompt: String? = nil) {
    self.generation = generation
    self.enhancePrompt = enhancePrompt
    self.describePrompt = describePrompt
  }

  /// The model's own system prompt for the task, if its folder has one.
  public func systemPrompt(for task: LanguageModelTask) -> String? {
    task == .enhance ? enhancePrompt : describePrompt
  }

  /// `system_prompt_t2i.txt` (Enhance), `system_prompt_i2i.txt` (Generate), else `system_prompt.txt`;
  /// sampling values from `generation_config.json`.
  public static func load(
    folder: URL, read: (URL) -> Data? = { try? Data(contentsOf: $0) }
  ) -> LanguageModelProfile {
    func text(_ name: String) -> String? {
      guard let data = read(folder.appendingPathComponent(name)), let string = String(data: data, encoding: .utf8)
      else { return nil }
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    var generation: Generation?
    if let data = read(folder.appendingPathComponent("generation_config.json")),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    {
      let found = Generation(
        temperature: (object["temperature"] as? NSNumber)?.doubleValue,
        topP: (object["top_p"] as? NSNumber)?.doubleValue, topK: (object["top_k"] as? NSNumber)?.intValue)
      if found != Generation() { generation = found }
    }
    let generic = text("system_prompt.txt")
    return LanguageModelProfile(
      generation: generation, enhancePrompt: text("system_prompt_t2i.txt") ?? generic,
      describePrompt: text("system_prompt_i2i.txt") ?? generic)
  }
}
