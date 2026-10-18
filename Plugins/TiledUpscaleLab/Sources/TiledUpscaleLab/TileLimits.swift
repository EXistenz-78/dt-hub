import Foundation

/// What the plug-in does with a picture that would be too big (spec §3).
enum TileLimits {
  enum Verdict: Equatable, Sendable { case ok, warn, refuse }

  static let maxSide = 16_384
  static let maxPixels = 268_435_456
  static let warnPixels = 100_000_000
  static let warnPasses = 100

  /// Refuse above 16 384 px on a side or 268 megapixels; ask for confirmation above 100 megapixels or 100 passes.
  static func verdict(width: Int, height: Int, passes: Int) -> Verdict {
    let pixels = width * height
    if width > maxSide || height > maxSide || pixels > maxPixels { return .refuse }
    if pixels > warnPixels || passes > warnPasses { return .warn }
    return .ok
  }
}
