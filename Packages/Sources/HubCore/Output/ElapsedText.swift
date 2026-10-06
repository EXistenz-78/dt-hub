import Foundation

/// How long an image took to make, as the strip of the Results window writes it: "42sec".
public enum ElapsedText {
  /// Whole seconds, never less than 1; nil when the time is not known.
  public static func label(_ seconds: TimeInterval?) -> String? {
    guard let seconds else { return nil }
    return "\(max(1, Int(seconds.rounded())))sec"
  }
}
