import Foundation

/// The colors of a palette are `#RRGGBB`, in capitals.
enum Palette {
  static let styleLimit = 16
  static let elementLimit = 5

  /// `#RRGGBB` from "#abc123", "abc123" or " #ABC123 "; nil for anything else.
  static func normalize(_ text: String) -> String? {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6, value.allSatisfy({ $0.isHexDigit }) else { return nil }
    return "#" + value.uppercased()
  }

  static func random(using generator: inout some RandomNumberGenerator) -> String {
    String(format: "#%06X", Int.random(in: 0...0xFFFFFF, using: &generator))
  }

  /// The red, green and blue of a color, each from 0 to 1.
  static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
    guard let value = normalize(hex), let number = Int(value.dropFirst(), radix: 16) else { return nil }
    return (Double((number >> 16) & 255) / 255, Double((number >> 8) & 255) / 255, Double(number & 255) / 255)
  }

  static func hex(red: Double, green: Double, blue: Double) -> String {
    func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
  }
}
