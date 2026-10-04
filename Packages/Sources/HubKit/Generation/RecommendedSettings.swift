import Foundation

/// The basic values Draw Things recommends for a model: steps, guidance, sampler and shift
/// (`2026-10-04-recommended-settings-design.md`).
public struct RecommendedValues: Equatable, Sendable {
  public var steps: Int
  public var guidanceScale: Double
  public var sampler: Sampler
  /// nil when the list gives none: the model computes it from the resolution, and the tab's shift stays as it is.
  public var shift: Double?
  /// nil when the list does not say.
  public var resolutionDependentShift: Bool?

  public init(
    steps: Int, guidanceScale: Double, sampler: Sampler, shift: Double? = nil, resolutionDependentShift: Bool? = nil
  ) {
    self.steps = steps
    self.guidanceScale = guidanceScale
    self.sampler = sampler
    self.shift = shift
    self.resolutionDependentShift = resolutionDependentShift
  }
}

/// The table of recommended values, by model and by family. It is a file in the app (`RecommendedSettings.json`,
/// made by `Scripts/make-recommended-settings.py` from Draw Things' own list); it is not in the Preset menu.
public struct RecommendedSettings: Equatable, Sendable {
  private var models: [String: RecommendedValues]
  private var families: [String: RecommendedValues]

  public init(models: [String: RecommendedValues] = [:], families: [String: RecommendedValues] = [:]) {
    self.models = models
    self.families = families
  }

  public static let empty = RecommendedSettings()

  /// Reads the file's JSON, leniently: an entry that is damaged, lacks a basic value or names a sampler
  /// Draw Things DT Hub does not know is left out; data that is not a table gives an empty one.
  public init(data: Data) {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      self.init()
      return
    }
    func read(_ section: Any?) -> [String: RecommendedValues] {
      var result: [String: RecommendedValues] = [:]
      for (key, raw) in (section as? [String: Any]) ?? [:] {
        guard let entry = raw as? [String: Any], let steps = entry["steps"] as? Int,
          let guidance = (entry["guidanceScale"] as? NSNumber)?.doubleValue, let samplerNumber = entry["sampler"] as? Int,
          let sampler = Sampler(rawValue: samplerNumber)
        else { continue }
        result[key] = RecommendedValues(
          steps: steps, guidanceScale: guidance, sampler: sampler, shift: (entry["shift"] as? NSNumber)?.doubleValue,
          resolutionDependentShift: entry["resolutionDependentShift"] as? Bool)
      }
      return result
    }
    self.init(models: read(root["models"]), families: read(root["families"]))
  }

  /// The model's file name without its quantization and extension: `flux_2_klein_9b_f16.ckpt` and
  /// `flux_2_klein_9b_q6p.ckpt` are both `flux_2_klein_9b`.
  public static func key(forFile file: String) -> String {
    var name = file
    if name.hasSuffix(".ckpt") { name.removeLast(5) }
    while let range = name.range(of: #"_(f16|f32|bf16|q\d+p|i8x|svd)$"#, options: .regularExpression) {
      name.removeSubrange(range)
    }
    return name
  }

  /// By the model's file, then by its family; nil when the table has neither.
  public func values(forFile file: String, family: String?) -> RecommendedValues? {
    models[Self.key(forFile: file)] ?? family.flatMap { families[$0] }
  }
}

extension GenerationParameters {
  /// The parameters with the recommended steps, guidance, sampler and shift (and the shift switch when the
  /// table says it), limited as the cards limit them. Nothing else changes: not the size, seed, batch, LoRAs,
  /// Advanced cards. A model whose list gives no shift leaves the shift as it is.
  public func applying(_ values: RecommendedValues) -> GenerationParameters {
    var copy = self
    copy.steps = values.steps
    copy.guidanceScale = values.guidanceScale
    copy.sampler = values.sampler
    if let shift = values.shift { copy.shift = shift }
    if let switchOn = values.resolutionDependentShift { copy.resolutionDependentShift = switchOn }
    return copy.clamped()
  }
}
