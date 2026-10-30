import Foundation

/// The values a video model starts with when the user picks it in the header: what Draw Things uses for the model,
/// plus the size, frames and decoding that make a clip fit in memory. Not in the recommended-settings table, which
/// only knows steps, guidance, sampler and shift.
public enum VideoDefaults {
  private struct Values {
    var steps: Int
    var sampler: Sampler
    var shift: Double
    var resolutionDependentShift: Bool?
    var width: Int
    var height: Int
    var numFrames: Int
    var shiftForAudio: Double?
    var tiledDecoding: Bool
    var hiresSize: (width: Int, height: Int)?
  }

  private static let fastH3 = Values(
    steps: 8, sampler: .ddimTrailing, shift: 12, resolutionDependentShift: false, width: 832, height: 512,
    numFrames: 124, shiftForAudio: 3, tiledDecoding: true, hiresSize: nil)
  private static let h3 = Values(
    steps: 50, sampler: .ddimTrailing, shift: 12, resolutionDependentShift: false, width: 576, height: 448,
    numFrames: 56, shiftForAudio: 3, tiledDecoding: true, hiresSize: nil)
  private static let ltx = Values(
    steps: 8, sampler: .tcdTrailing, shift: 5, resolutionDependentShift: false, width: 1280, height: 768,
    numFrames: 121, shiftForAudio: nil, tiledDecoding: false, hiresSize: (640, 384))

  /// The parameters with the model's video defaults, or nil when the family is not an enabled video family.
  /// Seed, batch count, LoRAs and prompt stay as they are; the batch size is 1.
  public static func applying(to parameters: GenerationParameters, file: String, family: String?) -> GenerationParameters? {
    guard let info = VideoFamilies.info(for: family) else { return nil }
    let values: Values
    if info.family == "ltx2.3" {
      values = ltx
    } else if file.hasPrefix("fasth3_omni") {
      values = fastH3
    } else {
      values = h3
    }
    var copy = parameters
    copy.steps = values.steps
    copy.guidanceScale = 1
    copy.sampler = values.sampler
    copy.shift = values.shift
    if let switchOn = values.resolutionDependentShift { copy.resolutionDependentShift = switchOn }
    copy.width = values.width
    copy.height = values.height
    copy.batchSize = 1
    copy.video.numFrames = values.numFrames
    if let audio = values.shiftForAudio { copy.video.shiftForAudio = audio }
    copy.video.usesSolAttention = false
    copy.advanced.teaCache = false
    if values.tiledDecoding {
      copy.advanced.tiledDecoding = true
      copy.advanced.decodingTileWidth = 256
      copy.advanced.decodingTileHeight = 256
      copy.advanced.decodingTileOverlap = 64
    }
    if let hires = values.hiresSize {
      copy.advanced.hiresFix = true
      copy.advanced.hiresFixWidth = hires.width
      copy.advanced.hiresFixHeight = hires.height
      copy.advanced.hiresFixStrength = 0.7
    } else {
      // A Hires fix left by the previous model (LTX) would send a two-pass job to a model that has none.
      copy.advanced.hiresFix = false
    }
    var clamped = copy.clamped()
    clamped.video = clamped.video.clamped(for: info)
    return clamped
  }
}
