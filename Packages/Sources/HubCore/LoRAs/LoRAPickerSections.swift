import Foundation
import HubKit

/// Groups LoRAs into picker sections by category and filters them by a search query.
public enum LoRAPickerSections {
  /// A group of LoRAs of one category; `category` nil means "no category".
  public struct Section: Equatable, Sendable {
    public var category: String?
    public var loras: [CatalogLoRA]

    public init(category: String?, loras: [CatalogLoRA]) {
      self.category = category
      self.loras = loras
    }
  }

  /// The known categories, in display order; LoRAs without one of these come last.
  public static let order: [String] = ["character", "style", "slider", "edit", "turbo"]

  /// The sections for `loras` matching `query` (substring of name or trigger, ignoring case, accents
  /// and surrounding whitespace; an empty query keeps all). Each section is sorted by name; empty
  /// sections are omitted.
  public static func make(loras: [CatalogLoRA], query: String) -> [Section] {
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: options, locale: nil)
    let matching =
      needle.isEmpty
      ? loras
      : loras.filter {
        $0.name.folding(options: options, locale: nil).contains(needle)
          || $0.trigger.folding(options: options, locale: nil).contains(needle)
      }
    let byName: (CatalogLoRA, CatalogLoRA) -> Bool = {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    func key(_ lora: CatalogLoRA) -> String? {
      lora.category.flatMap { order.contains($0) ? $0 : nil }
    }
    let categories: [String?] = order.map { Optional($0) } + [nil]
    return categories.compactMap { category in
      let group = matching.filter { key($0) == category }.sorted(by: byName)
      return group.isEmpty ? nil : Section(category: category, loras: group)
    }
  }
}
