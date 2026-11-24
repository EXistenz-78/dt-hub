import SwiftUI

/// I colori dei due tipi: gli stessi sul riquadro, sulla sua etichetta e nella scheda.
enum MingPalette {
  static func hex(for kind: MingKind) -> String {
    switch kind {
    case .object: return "#3EC8C8"
    case .text: return "#C77DFF"
    }
  }

  static func color(for kind: MingKind) -> Color {
    let value = Int(hex(for: kind).dropFirst(), radix: 16) ?? 0
    return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
  }
}
