import Foundation

/// Why the seam cannot be corrected on a picture (or at all).
enum PSSeamReason: Error, Equatable {
  case noResult
  case unreadable
  case notTwoToOne
  case heightNotMultipleOf64
  case tooBig
}

/// Where everything goes, for a panorama `width × height`: the panorama is rolled by half its width so that the seam is in the middle, the central
/// square (as tall as the panorama) is cut out, and its central half (the band) is what the model makes again.
struct PSSeamPlan: Equatable {
  var width: Int
  var height: Int
  /// The side of the square cut out, and the size of the pass.
  var square: Int
  /// The width of the band the model makes again (half the square).
  var bandWidth: Int
  /// The width of the soft edge on each side of the band when it is pasted back.
  var fade: Int

  /// The column of the rolled panorama where the old seam is (the boundary between the columns on its two sides).
  var seamX: Int { width - width / 2 }
  /// Where the square starts, and the band, in the rolled panorama.
  var cropX: Int { seamX - square / 2 }
  var bandX: Int { seamX - bandWidth / 2 }
  /// The number of columns the panorama is rolled by.
  var rollColumns: Int { width / 2 }
}

/// The correction of the seam: the constants (all in one place, to be changed with one line) and the plan for a size.
enum PSSeam {
  /// The saved preset the pass uses. Its model, prompt and parameters are the user's.
  static let presetName = "PANO Test"
  static let strength = 1.0
  /// How Draw Things treats the mask (blur 0…30, outset 0…100; the original is kept outside it).
  static let maskBlur = 24
  static let maskOutset = 0
  /// The band is this fraction of the square; the soft edge is `square / fadeDivisor`; the brightness is levelled with a blur of `square / toneRadiusDivisor`.
  static let bandFraction = 0.5
  static let fadeDivisor = 16
  static let toneRadiusDivisor = 32
  /// The biggest square the model takes without HiRes.
  static let maxSquare = 2048

  /// The plan for a panorama of this size, or the reason there is none: it must be 2:1 (4 % either way), its height a multiple of 64 (the pass takes
  /// only those) and not above what the model takes.
  static func plan(width: Int, height: Int) -> Result<PSSeamPlan, PSSeamReason> {
    guard width > 0, height > 0, abs(Double(width) / Double(height) / 2 - 1) <= 0.04 else { return .failure(.notTwoToOne) }
    guard height % 64 == 0 else { return .failure(.heightNotMultipleOf64) }
    guard height <= maxSquare else { return .failure(.tooBig) }
    let band = Int(Double(height) * bandFraction)
    return .success(PSSeamPlan(width: width, height: height, square: height, bandWidth: band, fade: height / fadeDivisor))
  }
}
