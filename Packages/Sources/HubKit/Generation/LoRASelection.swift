/// How a LoRA applies when a refiner runs (Draw Things `LoRAMode`, same raw values).
public enum LoRAMode: Int, CaseIterable, Identifiable, Codable, Sendable {
  case all = 0
  case base = 1
  case refiner = 2

  public var id: Int { rawValue }
}

/// A LoRA chosen in the LoRA card: file, weight and mode (spec §6, level 1).
public struct LoRASelection: Equatable, Codable, Sendable, Identifiable {
  public var id: String { file }
  public var file: String
  /// 1 = full strength; Draw Things accepts −1,5…2,5.
  public var weight: Double
  public var mode: LoRAMode
  /// Words that call the LoRA up. Kept apart from the prompt, so rewriting the prompt (for
  /// example with the LLM) never touches them; put in front of the prompt at RUN.
  public var trigger: String

  public static let weightRange = -1.5...2.5

  public init(file: String, weight: Double = 1, mode: LoRAMode = .all, trigger: String = "") {
    self.file = file
    self.weight = weight
    self.mode = mode
    self.trigger = trigger
  }

  /// Lenient: a missing weight, mode or trigger takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    file = try container.decode(String.self, forKey: .file)
    weight = (try? container.decodeIfPresent(Double.self, forKey: .weight)) ?? 1
    mode = (try? container.decodeIfPresent(LoRAMode.self, forKey: .mode)) ?? .all
    trigger = (try? container.decodeIfPresent(String.self, forKey: .trigger)) ?? ""
  }
}
