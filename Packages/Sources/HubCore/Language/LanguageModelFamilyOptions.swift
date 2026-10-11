import Foundation

/// The families offered by the Family menu of Settings › LLM.
public enum LanguageModelFamilyOptions {
  /// The families of the prompt guides with their labels, plus the connected server's families the guides
  /// do not know (shown by key), all sorted by label.
  public static func list(catalogFamilies: [String], library: PromptLibrary = .builtIn) -> [(key: String, label: String)] {
    var entries = library.families().map { (key: $0.id, label: $0.label) }
    let known = Set(entries.map(\.key))
    for key in Set(catalogFamilies) where !known.contains(key) {
      entries.append((key: key, label: key))
    }
    return entries.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }
}
