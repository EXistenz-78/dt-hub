import AppKit
import SwiftUI

/// Otto colori in rotazione: uno per elemento, lo stesso nel testo, sul canvas e nella scheda.
enum F3Palette {
  static let rgb: [(Double, Double, Double)] = [
    (0.24, 0.78, 0.78), (0.94, 0.71, 0.24), (0.78, 0.49, 1.00), (0.44, 0.81, 0.50),
    (1.00, 0.48, 0.48), (0.40, 0.65, 1.00), (1.00, 0.62, 0.80), (0.74, 0.80, 0.36),
  ]

  static func color(index: Int) -> Color {
    let c = rgb[((index % rgb.count) + rgb.count) % rgb.count]
    return Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: 1)
  }

  static func nsColor(index: Int) -> NSColor {
    let c = rgb[((index % rgb.count) + rgb.count) % rgb.count]
    return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
  }
}
