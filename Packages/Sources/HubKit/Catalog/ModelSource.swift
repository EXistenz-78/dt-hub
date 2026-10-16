/// Which of Draw Things' three model lists a model comes from (spec §4). The order is the one the picker shows.
public enum ModelSource: Int, CaseIterable, Comparable, Sendable {
  /// The models of the Draw Things app itself.
  case official
  /// The curated community list (`models.json`).
  case community
  /// The uncurated community list (`uncurated_models.json`).
  case uncurated

  public static func < (lhs: ModelSource, rhs: ModelSource) -> Bool { lhs.rawValue < rhs.rawValue }
}
