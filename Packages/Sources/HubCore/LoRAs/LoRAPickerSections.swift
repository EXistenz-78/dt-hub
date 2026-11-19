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

    /// The stable key of this section for the collapsed set ("none" for no category).
    public var key: String { LoRAPickerSections.key(of: category) }
  }

  /// The key under which a category is remembered as collapsed.
  public static func key(of category: String?) -> String { category ?? "none" }

  /// Whether a section shows its LoRAs: always while a search is active (so results are never
  /// hidden), otherwise unless the user collapsed it.
  public static func isExpanded(_ section: Section, collapsed: Set<String>, query: String) -> Bool {
    isSearching(query) || !collapsed.contains(section.key)
  }

  /// Whether `query` filters anything (not empty after trimming).
  public static func isSearching(_ query: String) -> Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// `collapsed` with `section` flipped. A no-op while searching, where every section is open.
  public static func toggled(_ section: Section, in collapsed: Set<String>, query: String) -> Set<String> {
    guard !isSearching(query) else { return collapsed }
    var result = collapsed
    if !result.insert(section.key).inserted { result.remove(section.key) }
    return result
  }

  /// The LoRAs actually listed, in order: those of the expanded sections.
  public static func visibleLoRAs(
    _ sections: [Section], collapsed: Set<String>, query: String
  ) -> [CatalogLoRA] {
    sections.filter { isExpanded($0, collapsed: collapsed, query: query) }.flatMap(\.loras)
  }

  /// Stored form of the collapsed set (sorted, comma-separated) for `@AppStorage`.
  public static func encode(collapsed: Set<String>) -> String {
    collapsed.sorted().joined(separator: ",")
  }

  public static func decode(collapsed stored: String) -> Set<String> {
    Set(stored.split(separator: ",").map(String.init))
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
