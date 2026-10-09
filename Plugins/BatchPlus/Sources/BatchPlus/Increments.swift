import Foundation

/// The numeric parameters of the Generation tab that can grow from one pass to the next. (The LoRA weights are
/// handled apart, one per file.)
enum BatchPlusKey: String, CaseIterable {
  case steps, guidanceScale, shift, cfgZeroInitSteps, seed

  /// Steps, the initial CFG-Zero steps and the seed only make sense as whole numbers.
  var isInteger: Bool { self == .steps || self == .cfgZeroInitSteps || self == .seed }
}

enum IncrementError: Error, Equatable {
  case notANumber
  case notAnInteger
}

/// Reads the text of an increment box.
enum IncrementParse {
  /// Comma or point, an optional sign. Empty or zero is `nil` (the parameter does not vary); anything that is not a
  /// number is an error, and so is a decimal where only a whole number makes sense.
  static func parse(_ text: String, integer: Bool) -> Result<Double?, IncrementError> {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
      .replacingOccurrences(of: "\u{2212}", with: "-")
    if cleaned.isEmpty { return .success(nil) }
    guard let value = Double(cleaned), value.isFinite else { return .failure(.notANumber) }
    if integer, value != value.rounded() { return .failure(.notAnInteger) }
    return .success(value == 0 ? nil : value)
  }
}

enum BatchPlusMath {
  /// `count` values, the first one `base`, each next one `increment` more. Rounded to six decimals, so 0.4 + 2 × 0.2 is
  /// 0.8 and not 0.8000000000000002.
  static func values(base: Double, increment: Double, count: Int) -> [Double] {
    (0..<max(count, 0)).map { ((base + Double($0) * increment) * 1e6).rounded() / 1e6 }
  }
}
