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

  public init(trigger: String? = nil, weight: Double? = nil, minWeight: Double? = nil, maxWeight: Double? = nil) {
    self.trigger = trigger
    self.weight = weight
    self.minWeight = minWeight
    self.maxWeight = maxWeight
  }

  var isEmpty: Bool { trigger == nil && weight == nil && minWeight == nil && maxWeight == nil }
}

/// The user's own trigger words and weights for the LoRAs of the server (`loras.json`). Draw Things' own files are never
/// touched: the server's values are inherited, and only what the user changed is kept here, by file name.
public struct LoRAOverrides: Equatable, Sendable {
  /// The weight every LoRA starts with.
  public static let defaultWeight = 1.0
  public static let weightRange = LoRASelection.weightRange

  public var entries: [String: LoRAOverride]

  public init(entries: [String: LoRAOverride] = [:]) {
    self.entries = entries
  }

  /// True when the user changed the trigger word or the weight of this LoRA.
  public func isChanged(_ lora: CatalogLoRA) -> Bool { entries[lora.file] != nil }

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

  /// Back to the server's trigger word and the default weight.
  public mutating func reset(_ lora: CatalogLoRA) {
    entries[lora.file] = nil
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
          defaultWeight: entry?.weight ?? Self.defaultWeight, minWeight: entry?.minWeight, maxWeight: entry?.maxWeight)
      },
      fileCount: catalog.fileCount, upscalers: catalog.upscalers, faceRestorers: catalog.faceRestorers)
  }

  private mutating func store(_ entry: LoRAOverride, for file: String) {
    entries[file] = entry.isEmpty ? nil : entry
  }
}
