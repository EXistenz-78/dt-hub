import Foundation


/// Reads a number typed in a card field. The whole text counts: a value outside the range
/// becomes the nearest bound (typing 200 in a 1…150 field gives 150), text that is not a
/// number gives nil so the field can go back to its value.
public enum NumberText {
  public static func int(_ text: String, in range: ClosedRange<Int>) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if let number = Int(trimmed) { return min(max(number, range.lowerBound), range.upperBound) }
    // Only digits but too long for Int: above any range.
    if !trimmed.isEmpty, trimmed.allSatisfy(\.isASCIIDigit) { return range.upperBound }
    return nil
  }

  /// Comma or point as decimal separator.
  public static func decimal(_ text: String, in range: ClosedRange<Double>) -> Double? {
    let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard let number = Double(normalized), number.isFinite else { return nil }
    return min(max(number, range.lowerBound), range.upperBound)
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
