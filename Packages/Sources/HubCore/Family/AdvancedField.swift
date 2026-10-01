import HubKit

/// The Advanced cards of the Generation tab (spec §6, level 2), in display order.
public enum AdvancedCard: String, CaseIterable, Identifiable, Sendable {
  case refiner, hiresFix, upscale, guidance, textEncoder, sdxl, performance, output

  public var id: String { rawValue }

  public var fields: [AdvancedField] { AdvancedField.allCases.filter { $0.card == self } }
}

/// One setting of the Advanced cards, with the values that go with it (a switch and its
/// sizes count as one). It knows when it applies, whether it differs from Draw Things'
/// default, and how to go back to it.
public enum AdvancedField: String, CaseIterable, Identifiable, Sendable {
  case refiner
  case hiresFix
  case upscaler
  case faceRestoration
  case guidanceEmbed
  case sharpness
  case stochasticSamplingGamma
  case clipSkip
  case t5TextEncoder
  case separateClipL
  case separateOpenClipG
  case separateT5
  case zeroNegativePrompt
  case sdxlConditioning
  case tiledDecoding
  case tiledDiffusion
  case teaCache
  case colorCalibration
  case compressionArtifacts

  public var id: String { rawValue }

  public var card: AdvancedCard {
    switch self {
    case .refiner: .refiner
    case .hiresFix: .hiresFix
    case .upscaler, .faceRestoration: .upscale
    case .guidanceEmbed, .sharpness, .stochasticSamplingGamma: .guidance
    case .clipSkip, .t5TextEncoder, .separateClipL, .separateOpenClipG, .separateT5, .zeroNegativePrompt: .textEncoder
    case .sdxlConditioning: .sdxl
    case .tiledDecoding, .tiledDiffusion, .teaCache: .performance
    case .colorCalibration, .compressionArtifacts: .output
    }
  }

  /// SDXL-derived versions: Kolors and SSD-1B use them too.
  static let sdxlFamilies: Set<String> = ["sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b"]
  static let sd3Families: Set<String> = ["sd3", "sd3_large"]

  /// Whether the field applies to the chosen model (nil = unknown: everything applies) and,
  /// for the sampling gamma, to the chosen sampler.
  public func isShown(for model: CatalogModel?, sampler: Sampler) -> Bool {
    let capabilities = model?.capabilities ?? .unknown
    let family = model?.family
    switch self {
    case .refiner, .hiresFix, .upscaler, .faceRestoration, .sharpness, .tiledDecoding, .tiledDiffusion,
      .colorCalibration, .compressionArtifacts:
      return true
    case .guidanceEmbed: return capabilities.guidanceEmbed
    case .stochasticSamplingGamma: return sampler == .tcd || sampler == .tcdTrailing
    case .clipSkip: return capabilities.clipSkip
    case .t5TextEncoder: return capabilities.optionalT5
    // A separate text only makes sense next to another encoder.
    case .separateClipL: return capabilities.clipL && (capabilities.openClipG || capabilities.t5)
    case .separateOpenClipG: return capabilities.openClipG && (capabilities.clipL || capabilities.t5)
    case .separateT5: return capabilities.t5 && (capabilities.clipL || capabilities.openClipG)
    case .zeroNegativePrompt:
      guard let family else { return true }
      return Self.sdxlFamilies.contains(family) || Self.sd3Families.contains(family)
    case .sdxlConditioning:
      guard let family else { return true }
      return Self.sdxlFamilies.contains(family)
    case .teaCache: return capabilities.teaCache
    }
  }

  /// True when the field's values differ from Draw Things' defaults.
  public func isModified(in advanced: AdvancedParameters) -> Bool {
    var reset = advanced
    reset.reset(self)
    return reset != advanced
  }
}

extension AdvancedParameters {
  /// Puts the field's values back to Draw Things' defaults.
  public mutating func reset(_ field: AdvancedField) {
    let d = Self.default
    switch field {
    case .refiner:
      refinerModel = d.refinerModel
      refinerStart = d.refinerStart
    case .hiresFix:
      hiresFix = d.hiresFix
      hiresFixWidth = d.hiresFixWidth
      hiresFixHeight = d.hiresFixHeight
      hiresFixStrength = d.hiresFixStrength
    case .upscaler:
      upscaler = d.upscaler
      upscalerScaleFactor = d.upscalerScaleFactor
    case .faceRestoration:
      faceRestoration = d.faceRestoration
    case .guidanceEmbed:
      guidanceEmbed = d.guidanceEmbed
      speedUpWithGuidanceEmbed = d.speedUpWithGuidanceEmbed
    case .sharpness:
      sharpness = d.sharpness
    case .stochasticSamplingGamma:
      stochasticSamplingGamma = d.stochasticSamplingGamma
    case .clipSkip:
      clipSkip = d.clipSkip
    case .t5TextEncoder:
      t5TextEncoder = d.t5TextEncoder
    case .separateClipL:
      separateClipL = d.separateClipL
      clipLText = d.clipLText
    case .separateOpenClipG:
      separateOpenClipG = d.separateOpenClipG
      openClipGText = d.openClipGText
    case .separateT5:
      separateT5 = d.separateT5
      t5Text = d.t5Text
    case .zeroNegativePrompt:
      zeroNegativePrompt = d.zeroNegativePrompt
    case .sdxlConditioning:
      aestheticScore = d.aestheticScore
      negativeAestheticScore = d.negativeAestheticScore
      cropTop = d.cropTop
      cropLeft = d.cropLeft
      originalWidth = d.originalWidth
      originalHeight = d.originalHeight
      targetWidth = d.targetWidth
      targetHeight = d.targetHeight
      negativeOriginalWidth = d.negativeOriginalWidth
      negativeOriginalHeight = d.negativeOriginalHeight
    case .tiledDecoding:
      tiledDecoding = d.tiledDecoding
      decodingTileWidth = d.decodingTileWidth
      decodingTileHeight = d.decodingTileHeight
      decodingTileOverlap = d.decodingTileOverlap
    case .tiledDiffusion:
      tiledDiffusion = d.tiledDiffusion
      diffusionTileWidth = d.diffusionTileWidth
      diffusionTileHeight = d.diffusionTileHeight
      diffusionTileOverlap = d.diffusionTileOverlap
    case .teaCache:
      teaCache = d.teaCache
      teaCacheStart = d.teaCacheStart
      teaCacheEnd = d.teaCacheEnd
      teaCacheThreshold = d.teaCacheThreshold
      teaCacheMaxSkipSteps = d.teaCacheMaxSkipSteps
    case .colorCalibration:
      colorCalibration = d.colorCalibration
    case .compressionArtifacts:
      compressionArtifacts = d.compressionArtifacts
      compressionQuality = d.compressionQuality
    }
  }

  /// Fields changed from the defaults, in card order (for the "Show advanced" switch).
  public var modifiedFields: [AdvancedField] {
    AdvancedField.allCases.filter { $0.isModified(in: self) }
  }

  /// Fields changed from the defaults that the chosen model does not use: kept, not sent
  /// (spec §6: "valori nascosti").
  public func hiddenModifiedFields(for model: CatalogModel?, sampler: Sampler) -> [AdvancedField] {
    modifiedFields.filter { !$0.isShown(for: model, sampler: sampler) }
  }
}
