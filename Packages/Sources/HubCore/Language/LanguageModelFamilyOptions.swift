import Foundation

/// The families offered by the Family menu of Settings › LLM.
public enum LanguageModelFamilyOptions {
  /// The families of the prompt guides with their labels, plus the connected server's families the guides
  /// do not know (shown by key), all sorted by label.
  public static func list(catalogFamilies: [String]) -> [(key: String, label: String)] {
    var entries = PromptGuides.all.map { (key: $0.key, label: $0.value.label) }
    for key in Set(catalogFamilies) where PromptGuides.all[key] == nil {
      entries.append((key: key, label: key))
    }
    return entries.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }
}
