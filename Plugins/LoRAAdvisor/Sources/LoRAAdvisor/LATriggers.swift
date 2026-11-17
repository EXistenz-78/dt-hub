import Foundation

/// Trigger words: the comparison is done by code, never by the model (spec §5).
enum LATriggers {
  /// Lower case, no accents, split on commas and white space, sorted, without duplicates.
  static func words(_ text: String) -> [String] {
    let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    let parts = folded.components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
    return Array(Set(parts.filter { !$0.isEmpty })).sorted()
  }

  /// What to offer to put in the Trigger field: nil when the page has no trigger or says what the field says,
  /// otherwise the words found, as written and without duplicates, joined by ", ".
  static func proposal(current: String, found: [String]) -> String? {
    let kept = found.flatMap { $0.components(separatedBy: ",") }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    var seen = Set<String>()
    let unique = kept.filter { seen.insert($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()).inserted }
    guard !unique.isEmpty else { return nil }
    let foundWords = words(unique.joined(separator: ", "))
    return foundWords == words(current) ? nil : unique.joined(separator: ", ")
  }
}
