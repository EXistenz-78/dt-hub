import Foundation

/// Why the seam cannot be corrected on a picture (or at all).
enum PSSeamReason: Error, Equatable {
  case noResult
  case unreadable
  case notTwoToOne
  /// The whole panorama is the pass, so both of its sides must be multiples of 64.
  case sizeNotMultipleOf64
  case tooBig
}

/// Where everything goes, for a panorama `width × height`: the panorama is rolled by half its width so that the seam is in the middle, a green
/// stripe (an eighth of the width) is painted over the seam, the model fills it, and the central quarter of the width (the band) is what is
/// pasted back into the panorama. The pass is the whole panorama.
struct PSSeamPlan: Equatable {
  var width: Int
  var height: Int
  /// The width of the green stripe the model fills.
  var greenWidth: Int
  /// The width of the band of the generated picture that is pasted back: wider than the green, so the soft edge falls on picture the model kept.
  var bandWidth: Int
  /// The width of the soft edge on each side of the band when it is pasted back.
  var fade: Int

  /// The column of the rolled panorama where the old seam is (the boundary between the columns on its two sides).
  var seamX: Int { width - width / 2 }
  /// Where the green and the band start, in the rolled panorama.
  var greenX: Int { seamX - greenWidth / 2 }
  var bandX: Int { seamX - bandWidth / 2 }
  /// The number of columns the panorama is rolled by.
  var rollColumns: Int { width / 2 }
}

/// The correction of the seam: the constants (all in one place, to be changed with one line) and the plan for a size.
enum PSSeam {
  /// The saved preset the pass uses: the panorama preset with the KV refiner. Its model, LoRA and parameters are the user's.
  static let presetName = PSPresets.fastName
  static let strength = 1.0
  /// The green is `1/greenDivisor` of the width, the band pasted back `1/bandDivisor`; the soft edge is `height / fadeDivisor`; the brightness is
  /// levelled with a blur of `height / toneRadiusDivisor`.
  static let greenDivisor = 8
  static let bandDivisor = 4
  static let fadeDivisor = 16
  static let toneRadiusDivisor = 32
  /// The longest side of a pass: what Draw Things makes without HiRes. A bigger pass would be cut to this by the app and the picture made would not
  /// be the size of the pass (the correction would find it out only at the end), so the button refuses it.
  static let maxSide = 2048

  /// The plan for a panorama of this size, or the reason there is none: it must be 2:1 (4 % either way), both sides multiples of 64 (the pass is the
  /// whole picture) and not above what the model takes.
  static func plan(width: Int, height: Int) -> Result<PSSeamPlan, PSSeamReason> {
    guard width > 0, height > 0, abs(Double(width) / Double(height) / 2 - 1) <= 0.04 else { return .failure(.notTwoToOne) }
    guard width % 64 == 0, height % 64 == 0 else { return .failure(.sizeNotMultipleOf64) }
    guard max(width, height) <= maxSide else { return .failure(.tooBig) }
    return .success(
      PSSeamPlan(width: width, height: height, greenWidth: width / greenDivisor, bandWidth: width / bandDivisor, fade: height / fadeDivisor))
  }

  /// The model the preset of the correction asks for, when its file says one (DT Hub applies the preset's parameters, but the model is the header's).
  static func presetModel(in folder: URL) -> String? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(presetName).json")),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let model = object["model"] as? String, !model.isEmpty
    else { return nil }
    return model
  }
}
