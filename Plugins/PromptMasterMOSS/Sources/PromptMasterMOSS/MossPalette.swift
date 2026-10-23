import SwiftUI

/// I colori dei cinque tipi: li stessi sul riquadro, sulla sua etichetta e nella scheda (mockup approvato).
enum MossPalette {
  static func hex(for label: MossLabel) -> String {
    switch label {
    case .object: return "#3EC8C8"
    case .character: return "#F0B43C"
    case .text: return "#C77DFF"
    case .panel: return "#6FCF7F"
    case .subject: return "#FF7A7A"
    }
  }

  static func color(for label: MossLabel) -> Color {
    let value = Int(hex(for: label).dropFirst(), radix: 16) ?? 0
    return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
  }
}
