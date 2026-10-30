import DTHubPluginKit
import Foundation

/// The three weights the user keeps for a LoRA: the lowest (Min), the one it starts with (Base) and the highest (Max).
/// They are kept by the app, with the data of its LoRA manager, so that the Generation tab knows them too.
enum LAWeights {
  struct Values: Equatable {
    var min: Double?
    var base: Double
    var max: Double?
  }

  static let range = LAAdvice.weightRange
  static let defaultBase = 1.0

  /// What the app keeps for the three values as typed (the same rules as there): all within -4…4, a Min above the Max
  /// brought down to it, and the Base between the two.
  static func normalised(min: Double?, base: Double?, max: Double?) -> Values {
    func clean(_ value: Double?) -> Double? {
      guard let value, value.isFinite else { return nil }
      return Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }
    var low = clean(min)
    let high = clean(max)
    if let l = low, let h = high, l > h { low = h }
    var base = clean(base) ?? defaultBase
    if let l = low { base = Swift.max(base, l) }
    if let h = high { base = Swift.min(base, h) }
    return Values(min: low, base: base, max: high)
  }

  /// The values of a LoRA of the catalog.
  static func values(of lora: DTHubCatalogLoRA) -> Values { Values(min: lora.minWeight, base: lora.weight, max: lora.maxWeight) }

  /// A number as typed (comma or point); nil for an empty or unreadable text.
  static func parse(_ text: String) -> Double? {
    let clean = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !clean.isEmpty, let value = Double(clean), value.isFinite else { return nil }
    return value
  }

  static func format(_ value: Double?) -> String {
    value.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
  }

  /// A suggested weight kept within the limits the user set for the LoRA.
  static func limited(_ weight: Double, by lora: DTHubCatalogLoRA) -> Double {
    var result = weight
    if let low = lora.minWeight { result = Swift.max(result, low) }
    if let high = lora.maxWeight { result = Swift.min(result, high) }
    return result
  }
}
