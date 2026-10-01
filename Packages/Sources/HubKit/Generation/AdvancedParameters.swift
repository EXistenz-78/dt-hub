import Foundation

/// Compression artifacts added to the output (Draw Things `CompressionMethod`, same raw values).
public enum CompressionArtifacts: Int, CaseIterable, Identifiable, Codable, Sendable {
  case none = 0
  case h264 = 1
  case h265 = 2
  case jpeg = 3

  public var id: Int { rawValue }
}

/// The level-2 parameters of the Advanced cards (spec §6), with Draw Things' own defaults.
/// Sizes are in pixels; 0 in a size means "automatic" (the model's native size for the Hires
/// fix start, the image size for the SDXL conditioning), as in Draw Things.
public struct AdvancedParameters: Equatable, Codable, Sendable {
  // Refiner: "" = none.
  public var refinerModel = ""
  public var refinerStart = 0.85
  // Hires fix.
  public var hiresFix = false
  public var hiresFixWidth = 0
  public var hiresFixHeight = 0
  public var hiresFixStrength = 0.7
  // Upscaler and face restoration: "" = none; scale 0 = the upscaler's own factor.
  public var upscaler = ""
  public var upscalerScaleFactor = 0
  public var faceRestoration = ""
  // Extra guidance.
  public var guidanceEmbed = 3.5
  public var speedUpWithGuidanceEmbed = true
  public var sharpness = 0.0
  public var stochasticSamplingGamma = 0.3
  // Text encoders.
  public var clipSkip = 1
  public var t5TextEncoder = true
  public var separateClipL = false
  public var clipLText = ""
  public var separateOpenClipG = false
  public var openClipGText = ""
  public var separateT5 = false
  public var t5Text = ""
  public var zeroNegativePrompt = false
  // SDXL conditioning.
  public var aestheticScore = 6.0
  public var negativeAestheticScore = 2.5
  public var cropTop = 0
  public var cropLeft = 0
  public var originalWidth = 0
  public var originalHeight = 0
  public var targetWidth = 0
  public var targetHeight = 0
  public var negativeOriginalWidth = 0
  public var negativeOriginalHeight = 0
  // Performance.
  public var tiledDecoding = false
  public var decodingTileWidth = 640
  public var decodingTileHeight = 640
  public var decodingTileOverlap = 128
  public var tiledDiffusion = false
  public var diffusionTileWidth = 1024
  public var diffusionTileHeight = 1024
  public var diffusionTileOverlap = 128
  public var teaCache = false
  public var teaCacheStart = 5
  /// -1 = up to the last step.
  public var teaCacheEnd = -1
  public var teaCacheThreshold = 0.06
  public var teaCacheMaxSkipSteps = 3
  // Output.
  public var colorCalibration = false
  public var compressionArtifacts = CompressionArtifacts.none
  public var compressionQuality = 43.1

  public init() {}

  public static let `default` = AdvancedParameters()

  /// Allowed ranges, used by the cards and by `clamped()`.
  public static let unitRange = 0.0...1.0
  public static let guidanceEmbedRange = 0.0...50.0
  public static let sharpnessRange = 0.0...30.0
  public static let clipSkipRange = 1...23
  public static let aestheticRange = 0.0...10.0
  /// SDXL conditioning sizes and crop; 0 = automatic.
  public static let conditioningRange = 0...8192
  public static let tileRange = 64...2048
  public static let overlapRange = 0...1024
  public static let teaCacheStepRange = 0...150
  public static let teaCacheEndRange = -1...150
  public static let teaCacheSkipRange = 1...50
  public static let qualityRange = 0.0...100.0
  /// 0 = the upscaler's own factor.
  public static let upscalerFactors = [0, 2, 4]

  /// An SDXL conditioning size as typed: 0 (or anything that rounds to it) = automatic,
  /// otherwise the nearest multiple of 64 up to 8192.
  public static func conditioningSize(_ value: Int) -> Int {
    let snapped = Int((Double(value) / 64).rounded()) * 64
    return min(max(snapped, conditioningRange.lowerBound), conditioningRange.upperBound)
  }

  /// An SDXL crop as typed: any pixel value from 0 to 8192.
  public static func crop(_ value: Int) -> Int {
    min(max(value, conditioningRange.lowerBound), conditioningRange.upperBound)
  }

  /// The same values forced into the allowed ranges; tile sizes on multiples of 64.
  public func clamped() -> AdvancedParameters {
    func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
      min(max(value, range.lowerBound), range.upperBound)
    }
    func tile(_ value: Int) -> Int { clamp(Int((Double(value) / 64).rounded()) * 64, Self.tileRange) }
    func hiresSize(_ value: Int) -> Int { value <= 0 ? 0 : GenerationParameters.snap(Double(value)) }
    var copy = self
    copy.refinerStart = clamp(refinerStart, Self.unitRange)
    copy.hiresFixWidth = hiresSize(hiresFixWidth)
    copy.hiresFixHeight = hiresSize(hiresFixHeight)
    copy.hiresFixStrength = clamp(hiresFixStrength, Self.unitRange)
    copy.upscalerScaleFactor = Self.upscalerFactors.contains(upscalerScaleFactor) ? upscalerScaleFactor : 0
    copy.guidanceEmbed = clamp(guidanceEmbed, Self.guidanceEmbedRange)
    copy.sharpness = clamp(sharpness, Self.sharpnessRange)
    copy.stochasticSamplingGamma = clamp(stochasticSamplingGamma, Self.unitRange)
    copy.clipSkip = clamp(clipSkip, Self.clipSkipRange)
    copy.aestheticScore = clamp(aestheticScore, Self.aestheticRange)
    copy.negativeAestheticScore = clamp(negativeAestheticScore, Self.aestheticRange)
    for keyPath in [
      \AdvancedParameters.cropTop, \.cropLeft, \.originalWidth, \.originalHeight, \.targetWidth,
      \.targetHeight, \.negativeOriginalWidth, \.negativeOriginalHeight,
    ] {
      copy[keyPath: keyPath] = clamp(copy[keyPath: keyPath], Self.conditioningRange)
    }
    copy.decodingTileWidth = tile(decodingTileWidth)
    copy.decodingTileHeight = tile(decodingTileHeight)
    copy.decodingTileOverlap = clamp(decodingTileOverlap, Self.overlapRange)
    copy.diffusionTileWidth = tile(diffusionTileWidth)
    copy.diffusionTileHeight = tile(diffusionTileHeight)
    copy.diffusionTileOverlap = clamp(diffusionTileOverlap, Self.overlapRange)
    copy.teaCacheStart = clamp(teaCacheStart, Self.teaCacheStepRange)
    copy.teaCacheEnd = clamp(teaCacheEnd, Self.teaCacheEndRange)
    copy.teaCacheThreshold = clamp(teaCacheThreshold, Self.unitRange)
    copy.teaCacheMaxSkipSteps = clamp(teaCacheMaxSkipSteps, Self.teaCacheSkipRange)
    copy.compressionQuality = clamp(compressionQuality, Self.qualityRange)
    return copy
  }

  /// Lenient: a missing or unreadable field takes its default, like `GenerationParameters`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    let d = Self.default
    refinerModel = value(.refinerModel, d.refinerModel)
    refinerStart = value(.refinerStart, d.refinerStart)
    hiresFix = value(.hiresFix, d.hiresFix)
    hiresFixWidth = value(.hiresFixWidth, d.hiresFixWidth)
    hiresFixHeight = value(.hiresFixHeight, d.hiresFixHeight)
    hiresFixStrength = value(.hiresFixStrength, d.hiresFixStrength)
    upscaler = value(.upscaler, d.upscaler)
    upscalerScaleFactor = value(.upscalerScaleFactor, d.upscalerScaleFactor)
    faceRestoration = value(.faceRestoration, d.faceRestoration)
    guidanceEmbed = value(.guidanceEmbed, d.guidanceEmbed)
    speedUpWithGuidanceEmbed = value(.speedUpWithGuidanceEmbed, d.speedUpWithGuidanceEmbed)
    sharpness = value(.sharpness, d.sharpness)
    stochasticSamplingGamma = value(.stochasticSamplingGamma, d.stochasticSamplingGamma)
    clipSkip = value(.clipSkip, d.clipSkip)
    t5TextEncoder = value(.t5TextEncoder, d.t5TextEncoder)
    separateClipL = value(.separateClipL, d.separateClipL)
    clipLText = value(.clipLText, d.clipLText)
    separateOpenClipG = value(.separateOpenClipG, d.separateOpenClipG)
    openClipGText = value(.openClipGText, d.openClipGText)
    separateT5 = value(.separateT5, d.separateT5)
    t5Text = value(.t5Text, d.t5Text)
    zeroNegativePrompt = value(.zeroNegativePrompt, d.zeroNegativePrompt)
    aestheticScore = value(.aestheticScore, d.aestheticScore)
    negativeAestheticScore = value(.negativeAestheticScore, d.negativeAestheticScore)
    cropTop = value(.cropTop, d.cropTop)
    cropLeft = value(.cropLeft, d.cropLeft)
    originalWidth = value(.originalWidth, d.originalWidth)
    originalHeight = value(.originalHeight, d.originalHeight)
    targetWidth = value(.targetWidth, d.targetWidth)
    targetHeight = value(.targetHeight, d.targetHeight)
    negativeOriginalWidth = value(.negativeOriginalWidth, d.negativeOriginalWidth)
    negativeOriginalHeight = value(.negativeOriginalHeight, d.negativeOriginalHeight)
    tiledDecoding = value(.tiledDecoding, d.tiledDecoding)
    decodingTileWidth = value(.decodingTileWidth, d.decodingTileWidth)
    decodingTileHeight = value(.decodingTileHeight, d.decodingTileHeight)
    decodingTileOverlap = value(.decodingTileOverlap, d.decodingTileOverlap)
    tiledDiffusion = value(.tiledDiffusion, d.tiledDiffusion)
    diffusionTileWidth = value(.diffusionTileWidth, d.diffusionTileWidth)
    diffusionTileHeight = value(.diffusionTileHeight, d.diffusionTileHeight)
    diffusionTileOverlap = value(.diffusionTileOverlap, d.diffusionTileOverlap)
    teaCache = value(.teaCache, d.teaCache)
    teaCacheStart = value(.teaCacheStart, d.teaCacheStart)
    teaCacheEnd = value(.teaCacheEnd, d.teaCacheEnd)
    teaCacheThreshold = value(.teaCacheThreshold, d.teaCacheThreshold)
    teaCacheMaxSkipSteps = value(.teaCacheMaxSkipSteps, d.teaCacheMaxSkipSteps)
    colorCalibration = value(.colorCalibration, d.colorCalibration)
    compressionArtifacts = value(.compressionArtifacts, d.compressionArtifacts)
    compressionQuality = value(.compressionQuality, d.compressionQuality)
  }
}
