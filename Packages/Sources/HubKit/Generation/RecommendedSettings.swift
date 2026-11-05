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
  /// The LoRAs the model starts with (file, weight, mode, trigger). nil leaves the tab's LoRAs as they are; a list,
  /// even an empty one, replaces them. Only the user's own saved defaults have it.
  public var loras: [LoRASelection]?

  public init(
    steps: Int, guidanceScale: Double, sampler: Sampler, shift: Double? = nil, resolutionDependentShift: Bool? = nil,
    loras: [LoRASelection]? = nil
  ) {
    self.steps = steps
    self.guidanceScale = guidanceScale
    self.sampler = sampler
    self.shift = shift
    self.resolutionDependentShift = resolutionDependentShift
    self.loras = loras
  }

  /// What the user saves as a model's default: the tab's sampling values and its LoRAs.
  public init(capturing parameters: GenerationParameters) {
    self.init(
      steps: parameters.steps, guidanceScale: parameters.guidanceScale, sampler: parameters.sampler,
      shift: parameters.shift, resolutionDependentShift: parameters.resolutionDependentShift, loras: parameters.loras)
  }

  /// The LoRAs of the list that are not in `installed`, in the list's order.
  public func missingLoRAs(installed: Set<String>) -> [String] {
    (loras ?? []).map(\.file).filter { !installed.contains($0) }
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
          resolutionDependentShift: entry["resolutionDependentShift"] as? Bool, loras: Self.readLoRAs(entry["loras"]))
      }
      return result
    }
    self.init(models: read(root["models"]), families: read(root["families"]))
  }

  /// A `loras` array, leniently: an element without a file, or that is not an object, is left out. nil when the entry has none.
  private static func readLoRAs(_ raw: Any?) -> [LoRASelection]? {
    guard let elements = raw as? [Any] else { return nil }
    return elements.compactMap { element in
      guard JSONSerialization.isValidJSONObject(element), let data = try? JSONSerialization.data(withJSONObject: element)
      else { return nil }
      return try? JSONDecoder().decode(LoRASelection.self, from: data)
    }
  }

  /// The list of official configurations Draw Things publishes (`configs.json`, the one its app downloads): for each
  /// model its basic values, as `Scripts/make-recommended-settings.py` reads them. Entries that use LoRAs (the "with
  /// Lightning" variants) are not a model's base values and are left out, and so are those without steps, guidance or
  /// sampler. The first entry that names a family is that family's fallback.
  public init(configurations data: Data) {
    var models: [String: RecommendedValues] = [:]
    var families: [String: RecommendedValues] = [:]
    for case let entry as [String: Any] in ((try? JSONSerialization.jsonObject(with: data)) as? [Any]) ?? [] {
      guard let configuration = entry["configuration"] as? [String: Any], let model = configuration["model"] as? String,
        (configuration["loras"] as? [Any] ?? []).isEmpty, let steps = configuration["steps"] as? Int,
        let guidance = (configuration["guidanceScale"] as? NSNumber)?.doubleValue,
        let sampler = (configuration["sampler"] as? Int).flatMap(Sampler.init(rawValue:))
      else { continue }
      let values = RecommendedValues(
        steps: steps, guidanceScale: guidance, sampler: sampler, shift: (configuration["shift"] as? NSNumber)?.doubleValue,
        resolutionDependentShift: configuration["resolutionDependentShift"] as? Bool)
      let key = Self.key(forFile: model)
      if models[key] == nil { models[key] = values }
      if let family = entry["version"] as? String, !family.isEmpty, families[family] == nil { families[family] = values }
    }
    self.init(models: models, families: families)
  }

  /// This table with what a newer list knows: its models are added and win over the ones here; of its families only
  /// those this table does not have are taken (a new variant listed first, as a Turbo, must not become what every
  /// other model of the family falls back to).
  public func merging(_ live: RecommendedSettings) -> RecommendedSettings {
    RecommendedSettings(
      models: models.merging(live.models) { _, new in new }, families: families.merging(live.families) { old, _ in old })
  }

  /// This table with the entries of `overrides` (the user's own defaults) on top: its models win over the ones here,
  /// whatever the online list said. Families are not touched.
  public func overriding(with overrides: RecommendedSettings) -> RecommendedSettings {
    RecommendedSettings(models: models.merging(overrides.models) { _, new in new }, families: families)
  }

  /// This table with `values` as the model's entry (by its key, so for every quantization of the model).
  public func setting(_ values: RecommendedValues, forFile file: String) -> RecommendedSettings {
    var copy = self
    copy.models[Self.key(forFile: file)] = values
    return copy
  }

  /// This table without the model's own entry (its family's fallback stays).
  public func removingModel(forFile file: String) -> RecommendedSettings {
    var copy = self
    copy.models[Self.key(forFile: file)] = nil
    return copy
  }

  /// True when the table has an entry of its own for the model, not only its family's.
  public func hasModel(forFile file: String) -> Bool {
    models[Self.key(forFile: file)] != nil
  }

  /// The table as the file keeps it (`{"models":…,"families":…}`), readable again by `init(data:)`.
  public func encoded() -> Data {
    struct Entry: Encodable {
      var steps: Int
      var guidanceScale: Double
      var sampler: Int
      var shift: Double?
      var resolutionDependentShift: Bool?
      var loras: [LoRASelection]?
    }
    struct File: Encodable {
      var models: [String: Entry]
      var families: [String: Entry]
    }
    func entries(_ table: [String: RecommendedValues]) -> [String: Entry] {
      table.mapValues {
        Entry(
          steps: $0.steps, guidanceScale: $0.guidanceScale, sampler: $0.sampler.rawValue, shift: $0.shift,
          resolutionDependentShift: $0.resolutionDependentShift, loras: $0.loras)
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return (try? encoder.encode(File(models: entries(models), families: entries(families)))) ?? Data()
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
  /// table says it), limited as the cards limit them. Nothing else changes: not the size, seed, batch,
  /// Advanced cards. A model whose list gives no shift leaves the shift as it is.
  public func applying(_ values: RecommendedValues) -> GenerationParameters {
    applying(values, installedLoRAs: nil)
  }

  /// As `applying(_:)`, and when the values carry a LoRA list it replaces the tab's LoRAs, without those not in
  /// `installedLoRAs` (nil: nothing is known about the server, none is left out).
  public func applying(_ values: RecommendedValues, installedLoRAs: Set<String>?) -> GenerationParameters {
    var copy = self
    if let loras = values.loras {
      copy.loras = loras.filter { installedLoRAs?.contains($0.file) ?? true }
    }
    copy.steps = values.steps
    copy.guidanceScale = values.guidanceScale
    copy.sampler = values.sampler
    if let shift = values.shift { copy.shift = shift }
    if let switchOn = values.resolutionDependentShift { copy.resolutionDependentShift = switchOn }
    return copy.clamped()
  }
}
