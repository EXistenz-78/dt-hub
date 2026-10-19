import Foundation

extension String {
  /// JSON text with every character outside ASCII written as `\uXXXX` (UTF-16 units, so a character above the Basic Multilingual
  /// Plane is a surrogate pair). The EXIF "UserComment" of a PNG is stored as ASCII by ImageIO: an accent, a "×" or a Japanese
  /// character in it came back as "?". In valid JSON a non-ASCII character only occurs inside a string, where the escape is
  /// read back as the same character by any JSON reader (DT Hub's, Draw Things', DTInspector's).
  public var jsonASCIIEscaped: String {
    var escaped = ""
    escaped.reserveCapacity(utf8.count)
    for scalar in unicodeScalars {
      if scalar.isASCII {
        escaped.unicodeScalars.append(scalar)
      } else {
        for unit in String(scalar).utf16 { escaped += String(format: "\\u%04x", unit) }
      }
    }
    return escaped
  }
}
