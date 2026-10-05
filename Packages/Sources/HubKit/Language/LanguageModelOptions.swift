import Foundation

/// How a question to the language model is asked (the `system` and `options` of a plug-in's `llm` message).
/// Every field is optional: nil keeps the default (no system prompt, temperature 0.6, 1024 tokens, the
/// thinking setting of the model's own chat template).
public struct LanguageModelOptions: Equatable, Sendable {
  public var system: String?
  public var temperature: Double?
  public var topP: Double?
  public var topK: Int?
  public var presencePenalty: Double?
  public var maxTokens: Int?
  /// Lets a reasoning model think before it answers (`enable_thinking` of the chat template).
  public var thinking: Bool?

  public static let temperatureRange = 0.0...2.0
  public static let topPRange = 0.0...1.0
  public static let topKRange = 0...200
  public static let presencePenaltyRange = -2.0...2.0
  public static let maxTokensRange = 1...32768

  public init(
    system: String? = nil, temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil,
    presencePenalty: Double? = nil, maxTokens: Int? = nil, thinking: Bool? = nil
  ) {
    self.system = system
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.presencePenalty = presencePenalty
    self.maxTokens = maxTokens
    self.thinking = thinking
  }

  /// Reads a plug-in's message: `system` (a string) and `options` (an object with `temperature`, `topP`,
  /// `topK`, `presencePenalty`, `maxTokens`, `thinking`). A number out of range is brought into range, a
  /// value of the wrong kind is left out, an unknown key is ignored.
  public init(message: [String: Any]) {
    let options = message["options"] as? [String: Any] ?? [:]
    func number(_ key: String) -> Double? { (options[key] as? NSNumber)?.doubleValue }
    func flag(_ key: String) -> Bool? { (options[key] as? NSNumber).flatMap { Self.isBoolean($0) ? $0.boolValue : nil } }
    let system = (message["system"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    self.init(
      system: system, temperature: number("temperature"), topP: number("topP"),
      topK: number("topK").map { Int($0.rounded()) }, presencePenalty: number("presencePenalty"),
      maxTokens: number("maxTokens").map { Int($0.rounded()) }, thinking: flag("thinking"))
    self = clamped()
  }

  /// The numbers forced into their ranges.
  public func clamped() -> LanguageModelOptions {
    var copy = self
    copy.temperature = temperature.map { min(max($0, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound) }
    copy.topP = topP.map { min(max($0, Self.topPRange.lowerBound), Self.topPRange.upperBound) }
    copy.topK = topK.map { min(max($0, Self.topKRange.lowerBound), Self.topKRange.upperBound) }
    copy.presencePenalty = presencePenalty.map {
      min(max($0, Self.presencePenaltyRange.lowerBound), Self.presencePenaltyRange.upperBound)
    }
    copy.maxTokens = maxTokens.map { min(max($0, Self.maxTokensRange.lowerBound), Self.maxTokensRange.upperBound) }
    return copy
  }

  private static func isBoolean(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
}
