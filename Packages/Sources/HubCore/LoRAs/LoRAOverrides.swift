import Foundation
import HubKit

/// What the user changed for one LoRA. A field that is nil is not changed: the server's value (or the default) holds.
public struct LoRAOverride: Equatable, Codable, Sendable {
  /// Present (even empty, which means "no trigger word") when the user changed it.
  public var trigger: String?
  /// Present when the user chose another weight than the default.
  public var weight: Double?
  /// The lowest and the highest weight the user allows for the LoRA (nil: no limit).
  public var minWeight: Double?
  public var maxWeight: Double?
  /// One of `LoRAOverrides.categories` (nil: not set).
  public var category: String?
  /// What a turbo LoRA needs: the number of steps, the guidance and the shift (nil: not set).
  public var steps: Int?
  public var guidance: Double?
  public var shift: Double?

  public init(
    trigger: String? = nil, weight: Double? = nil, minWeight: Double? = nil, maxWeight: Double? = nil,
    category: String? = nil, steps: Int? = nil, guidance: Double? = nil, shift: Double? = nil
  ) {
    self.category = category
    self.steps = steps
    self.guidance = guidance
    self.shift = shift
    self.trigger = trigger
    self.weight = weight
    self.minWeight = minWeight
    self.maxWeight = maxWeight
  }

  var isEmpty: Bool {
    trigger == nil && weight == nil && minWeight == nil && maxWeight == nil && category == nil && steps == nil
      && guidance == nil && shift == nil
  }
}

/// What to do with one field in an update: leave it, clear it (back to the server's value or nothing), or set it.
public enum LoRAPatch<Value: Equatable & Sendable>: Equatable, Sendable {
  case keep
  case clear
  case set(Value)
}

/// A change to the trigger word, the category and the turbo settings of one LoRA, field by field (LoRA Advisor).
public struct LoRASettingsUpdate: Equatable, Sendable {
  public var trigger: LoRAPatch<String>
  public var category: LoRAPatch<String>
  public var steps: LoRAPatch<Int>
  public var guidance: LoRAPatch<Double>
  public var shift: LoRAPatch<Double>

  public init(
    trigger: LoRAPatch<String> = .keep, category: LoRAPatch<String> = .keep, steps: LoRAPatch<Int> = .keep,
    guidance: LoRAPatch<Double> = .keep, shift: LoRAPatch<Double> = .keep
  ) {
    self.trigger = trigger
    self.category = category
    self.steps = steps
    self.guidance = guidance
    self.shift = shift
  }
}

/// The user's own trigger words and weights for the LoRAs of the server (`loras.json`). Draw Things' own files are never
/// touched: the server's values are inherited, and only what the user changed is kept here, by file name.
public struct LoRAOverrides: Equatable, Sendable {
  /// The weight every LoRA starts with.
  public static let defaultWeight = 1.0
  public static let weightRange = LoRASelection.weightRange
  /// The kinds of LoRA the user can choose from.
  public static let categories: Set<String> = ["character", "style", "slider", "edit", "turbo"]
  public static let stepsRange = 1...200
  /// The range of the guidance and of the shift.
  public static let numberRange = 0.0...50.0

  public var entries: [String: LoRAOverride]

  public init(entries: [String: LoRAOverride] = [:]) {
    self.entries = entries
  }

  /// True when the user changed the trigger word or the weight of this LoRA.
  public func isChanged(_ lora: CatalogLoRA) -> Bool { entries[lora.file] != nil }

  /// True when the user changed the trigger word, the weight or its limits: what Manage LoRAs shows and can reset.
  public func hasManagerChanges(_ lora: CatalogLoRA) -> Bool {
    guard let entry = entries[lora.file] else { return false }
    return entry.trigger != nil || entry.weight != nil || entry.minWeight != nil || entry.maxWeight != nil
  }

  /// Another trigger word than the server's (empty = none). The server's own word, or the same after trimming, is no
  /// change at all.
  public mutating func setTrigger(_ text: String, for lora: CatalogLoRA) {
    let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var entry = entries[lora.file] ?? LoRAOverride()
    entry.trigger = word == lora.trigger ? nil : word
    store(entry, for: lora.file)
  }

  /// Another weight than the default, brought into the range. Nil, or the default itself, is no change.
  public mutating func setWeight(_ value: Double?, for lora: CatalogLoRA) {
    var entry = entries[lora.file] ?? LoRAOverride()
    if let value, value.isFinite {
      let clamped = min(max(value, Self.weightRange.lowerBound), Self.weightRange.upperBound)
      entry.weight = clamped == Self.defaultWeight ? nil : clamped
    } else {
      entry.weight = nil
    }
    store(entry, for: lora.file)
  }

  /// The three weights of a LoRA together (LoRA Advisor): lowest, default and highest. A nil is cleared; all are brought
  /// into the range, and the default into the limits (Min ≤ Base ≤ Max; a Min above the Max is raised to it).
  public mutating func setWeights(min low: Double?, base: Double?, max high: Double?, for lora: CatalogLoRA) {
    let range = Self.weightRange
    func clean(_ value: Double?) -> Double? {
      guard let value, value.isFinite else { return nil }
      return Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }
    var low = clean(low)
    let high = clean(high)
    if let l = low, let h = high, l > h { low = h }
    var base = clean(base)
    if let b = base {
      if let l = low { base = Swift.max(b, l) }
      if let h = high, let b2 = base { base = Swift.min(b2, h) }
    }
    var entry = entries[lora.file] ?? LoRAOverride()
    entry.minWeight = low
    entry.maxWeight = high
    // With a limit the weight is written even when it is the default, so the three go together in the file.
    entry.weight = base == Self.defaultWeight && low == nil && high == nil ? nil : base
    store(entry, for: lora.file)
  }

  /// Applies an update field by field: `.keep` leaves it, `.clear` removes the user's value, `.set` replaces it. The
  /// trigger is trimmed (the server's own word is no change); an unknown category and a number that is not finite are
  /// refused (the field stays as it was); numbers are brought into their range.
  public mutating func apply(_ update: LoRASettingsUpdate, for lora: CatalogLoRA) {
    var entry = entries[lora.file] ?? LoRAOverride()
    switch update.trigger {
    case .keep: break
    case .clear: entry.trigger = nil
    case .set(let text):
      let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
      entry.trigger = word == lora.trigger ? nil : word
    }
    switch update.category {
    case .keep: break
    case .clear: entry.category = nil
    case .set(let name): if Self.categories.contains(name) { entry.category = name }
    }
    switch update.steps {
    case .keep: break
    case .clear: entry.steps = nil
    case .set(let value): entry.steps = Swift.min(Swift.max(value, Self.stepsRange.lowerBound), Self.stepsRange.upperBound)
    }
    switch update.guidance {
    case .keep: break
    case .clear: entry.guidance = nil
    case .set(let value): if let clean = Self.inRange(value) { entry.guidance = clean }
    }
    switch update.shift {
    case .keep: break
    case .clear: entry.shift = nil
    case .set(let value): if let clean = Self.inRange(value) { entry.shift = clean }
    }
    store(entry, for: lora.file)
  }

  /// The number inside `numberRange`; nil when it is not finite.
  static func inRange(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return Swift.min(Swift.max(value, numberRange.lowerBound), numberRange.upperBound)
  }

  /// Back to the server's trigger word and the default weight (no limits). The category and the turbo values stay: they
  /// are not shown in Manage LoRAs, so resetting there never erases them.
  public mutating func reset(_ lora: CatalogLoRA) {
    guard var entry = entries[lora.file] else { return }
    entry.trigger = nil
    entry.weight = nil
    entry.minWeight = nil
    entry.maxWeight = nil
    store(entry, for: lora.file)
  }

  /// The catalog with the user's values: the trigger word is theirs if they changed it, the server's otherwise (empty when
  /// the server has none); the weight is theirs or the default, whatever the server says. LoRAs the server no longer has
  /// are ignored (their entries stay for when they come back).
  public func apply(to catalog: ModelCatalog) -> ModelCatalog {
    ModelCatalog(
      models: catalog.models,
      loras: catalog.loras.map { lora in
        let entry = entries[lora.file]
        return CatalogLoRA(
          file: lora.file, name: lora.name, family: lora.family, trigger: entry?.trigger ?? lora.trigger,
          defaultWeight: entry?.weight ?? Self.defaultWeight, minWeight: entry?.minWeight, maxWeight: entry?.maxWeight,
          category: entry?.category, steps: entry?.steps, guidance: entry?.guidance, shift: entry?.shift)
      },
      fileCount: catalog.fileCount, upscalers: catalog.upscalers, faceRestorers: catalog.faceRestorers)
  }

  private mutating func store(_ entry: LoRAOverride, for file: String) {
    entries[file] = entry.isEmpty ? nil : entry
  }
}
