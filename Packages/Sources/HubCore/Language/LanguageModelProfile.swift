import Foundation
import HubKit

/// What an LLM's own folder says about how to use it: its system prompt and sampling values (and, for BFL's prompt upsampler,
/// its official prompts).
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

  /// The official prompts of Black Forest Labs' prompt upsampler (`flux-3-image-klein-pup`), from the `system_prompts.json` that
  /// ships with the model: `t2i` for a request without pictures, `i2i` for one with pictures (and for Generate).
  public struct Pup: Equatable, Sendable {
    public var t2i: String
    public var i2i: String
    /// The prompts for a prompt that carries a table of boxes (`t2i_bbox`, `i2i_bbox`); nil when the file lacks them.
    public var t2iBbox: String?
    public var i2iBbox: String?

    public init(t2i: String, i2i: String, t2iBbox: String? = nil, i2iBbox: String? = nil) {
      self.t2i = t2i
      self.i2i = i2i
      self.t2iBbox = t2iBbox
      self.i2iBbox = i2iBbox
    }
  }

  /// A prompt-expansion model that ships its own request (MiniMax-H3-Image-PE): `prompt/t2i/system_prompt.txt` and
  /// `prompt/t2i/task_prompt.txt` (a template, the request goes where `{}` is) for a request without pictures,
  /// `prompt/edit/task_prompt.txt` (fixed, no system prompt) for one with pictures, and the sampling values of
  /// `prompt/t2i/request_params.json`. The task prompts are kept as they are in the files, to the last newline.
  public struct Expander: Equatable, Sendable {
    public var t2iSystem: String
    public var t2iTask: String
    /// Nil when the folder has no edit prompt: pictures are then left out.
    public var editTask: String?
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    /// Thinking included.
    public var maxTokens: Int

    public init(
      t2iSystem: String, t2iTask: String, editTask: String? = nil, temperature: Double = 1.0, topP: Double = 0.95,
      topK: Int = 20, maxTokens: Int = 4096
    ) {
      self.t2iSystem = t2iSystem
      self.t2iTask = t2iTask
      self.editTask = editTask
      self.temperature = temperature
      self.topP = topP
      self.topK = topK
      self.maxTokens = maxTokens
    }
  }

  public var generation: Generation?
  /// Set when the folder has the expander's `prompt/t2i/` files: the model then gets its own request.
  public var expander: Expander?
  /// Set when the folder has the PUP's `system_prompts.json`: the model then writes prompts in its own formats.
  public var pup: Pup?
  private var enhancePrompt: String?
  private var enhanceWithImagesPrompt: String?
  private var describePrompt: String?

  public init(
    generation: Generation? = nil, enhancePrompt: String? = nil, describePrompt: String? = nil,
    enhanceWithImagesPrompt: String? = nil, pup: Pup? = nil, expander: Expander? = nil
  ) {
    self.generation = generation
    self.pup = pup
    self.expander = expander
    self.enhancePrompt = enhancePrompt
    self.describePrompt = describePrompt
    self.enhanceWithImagesPrompt = enhanceWithImagesPrompt
  }

  /// The model's own system prompt for the task, if its folder has one.
  public func systemPrompt(for task: LanguageModelTask) -> String? {
    systemPrompt(for: task, withImages: false)
  }

  /// Enhance with pictures attached prefers `system_prompt_i2i.txt` (then `system_prompt.txt`), never the t2i one.
  public func systemPrompt(for task: LanguageModelTask, withImages: Bool) -> String? {
    if task == .enhance { return withImages ? enhanceWithImagesPrompt : enhancePrompt }
    return describePrompt
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
    var pup: Pup?
    if let data = read(folder.appendingPathComponent("system_prompts.json")),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let t2i = (object["t2i"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t2i.isEmpty,
      let i2i = (object["i2i"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !i2i.isEmpty
    {
      func optional(_ key: String) -> String? {
        let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
      }
      pup = Pup(t2i: t2i, i2i: i2i, t2iBbox: optional("t2i_bbox"), i2iBbox: optional("i2i_bbox"))
    }
    func raw(_ name: String) -> String? {
      guard let data = read(folder.appendingPathComponent(name)), let string = String(data: data, encoding: .utf8),
        !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return nil }
      return string
    }
    var expander: Expander?
    if let system = text("prompt/t2i/system_prompt.txt"), let task = raw("prompt/t2i/task_prompt.txt"), task.contains("{}") {
      var found = Expander(t2iSystem: system, t2iTask: task, editTask: raw("prompt/edit/task_prompt.txt"))
      if let data = read(folder.appendingPathComponent("prompt/t2i/request_params.json")),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      {
        if let value = (object["temperature"] as? NSNumber)?.doubleValue { found.temperature = value }
        if let value = (object["top_p"] as? NSNumber)?.doubleValue { found.topP = value }
        if let value = (object["top_k"] as? NSNumber)?.intValue { found.topK = value }
        if let value = (object["max_tokens"] as? NSNumber)?.intValue, value > 0 { found.maxTokens = value }
      }
      expander = found
    }
    let generic = text("system_prompt.txt")
    return LanguageModelProfile(
      generation: generation, enhancePrompt: text("system_prompt_t2i.txt") ?? generic,
      describePrompt: text("system_prompt_i2i.txt") ?? generic,
      enhanceWithImagesPrompt: text("system_prompt_i2i.txt") ?? generic, pup: pup, expander: expander)
  }
}
