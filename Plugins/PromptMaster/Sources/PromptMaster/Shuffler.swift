import Foundation

/// What the Shuffle picks from: the photographic or the artistic side of the vocabulary.
enum StyleMode: String, Codable, Sendable { case photo, art }

/// The Shuffle button of the list (as in Prompt Master 2.0): a new random selection, one term for each category the
/// family keeps, except that the categories of the medium share one draw. The group of technical terms (quality,
/// negative, text) is never shuffled. The user's own terms are not picked.
enum Shuffler {
  /// Categories picked in both modes.
  static let common = [
    "mood_aesthetic_register", "atmosphere", "color_harmony", "genre_aesthetic", "atmospheric_fx",
    "mood", "mood_emotional_tone",
    "light_source", "light_quality", "light_scheme",
    "background_setup",
    "color_palette", "pose_gesture", "expression_gaze", "environment_natural", "environment_built", "time_weather",
    "material_natural", "material_manmade", "surface_finish",
  ]
  static let photoOnly = ["optical_fx", "framing", "camera_angle", "composition", "lens_focus", "photo_genre"]
  static let artOnly = [
    "art_movement", "design_movement", "anime_cartoon_style", "cultural_tradition",
    "artist_classical", "artist_modern", "artist_illustration",
  ]
  static let photoMedium = ["medium_digital_3d", "film_stock_process"]
  static let artMedium = ["medium_digital_3d", "medium_paint_draw", "medium_print_craft"]

  static func pick(
    database: PromptDatabase, hidden: Set<String>, mode: StyleMode, using generator: inout some RandomNumberGenerator
  ) -> [String] {
    let restricted = Set(database.groups.filter { $0.restricted == true }.map(\.id))
    let categories = Dictionary(uniqueKeysWithValues: database.categories.map { ($0.id, $0) })
    func eligible(_ id: String) -> PMCategory? {
      guard let category = categories[id], !category.terms.isEmpty, !hidden.contains(id),
        !restricted.contains(category.group)
      else { return nil }
      return category
    }
    var picked: [String] = []
    for id in common + (mode == .photo ? photoOnly : artOnly) {
      if let category = eligible(id), let term = category.terms.randomElement(using: &generator) { picked.append(term.id) }
    }
    let pool = (mode == .photo ? photoMedium : artMedium).compactMap(eligible).flatMap(\.terms)
    if let term = pool.randomElement(using: &generator) { picked.append(term.id) }
    return picked
  }
}
