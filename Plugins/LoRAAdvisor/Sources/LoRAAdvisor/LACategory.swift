import Foundation

/// The kind of a LoRA (spec §1). A LoRA with an unknown or missing category has none.
enum LACategory: String, CaseIterable {
  case character, style, slider, edit, turbo

  /// nil for a name that is not one of the five.
  init?(raw: String?) {
    guard let raw, let category = LACategory(rawValue: raw) else { return nil }
    self = category
  }

  func name(italian: Bool) -> String {
    switch self {
    case .character: italian ? "Personaggio" : "Character"
    case .style: italian ? "Stile" : "Style"
    case .slider: "Slider"
    case .edit: "Edit"
    case .turbo: "Turbo"
    }
  }
}
