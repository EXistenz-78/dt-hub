import Foundation
import HubKit

// The compute-unit (CU) estimate of one request, ported from Draw Things (GPL-3.0):
// Libraries/ModelZoo/Sources/ComputeUnits.swift and the CFG helpers of Libraries/SwiftDiffusion/Sources/Samplers/Sampler.swift,
// at drawthingsai/draw-things-community commit 3338389349ad7771e1b626e60913bf8c4fff3a26. The formula and the per-family
// calls are the original's; the input is DT Hub's `CUInputs` instead of Draw Things' `GenerationConfiguration`.

/// The families the estimate covers (the keys are Draw Things' model versions). A family not listed has no estimate.
enum CUFamily: String {
  case zImage = "z_image"
  case qwenImage = "qwen_image"
  case qwenImage2_1 = "qwen_image_2.1"
  case ernieImage = "ernie_image"
  case ideogram4 = "ideogram_4"
  case seedvr2_3b = "seedvr2_3b"
  case seedvr2_7b = "seedvr2_7b"
  case flux1 = "flux1"
  case flux2 = "flux2"
  case flux2_9b = "flux2_9b"
  case flux2_4b = "flux2_4b"
  case krea2 = "krea_2"
  case sd3 = "sd3"
  case sd3Large = "sd3_large"
  case pixart = "pixart"
  case auraflow = "auraflow"
  case hiDreamI1 = "hidream_i1"
  case hiDreamO1 = "hidream_o1"
}

/// The spec's `modifier` of a model (Draw Things' `SamplerModifier`).
enum CUModifier {
  case none, editing, inpainting, depth, canny, double
  case kontext, kontextKv, qwenimageEditPlus, qwenimageEdit2511, fl2va, ref2va, qwenimageLayered

  init(key: String?) {
    switch key {
    case "editing": self = .editing
    case "inpainting": self = .inpainting
    case "depth": self = .depth
    case "canny": self = .canny
    case "double": self = .double
    case "kontext": self = .kontext
    case "kontext_kv": self = .kontextKv
    case "qwenimage_edit_plus": self = .qwenimageEditPlus
    case "qwenimage_edit_2511": self = .qwenimageEdit2511
    case "fl2va": self = .fl2va
    case "ref2va": self = .ref2va
    case "qwenimage_layered": self = .qwenimageLayered
    default: self = .none
    }
  }
}

enum ComputeUnitsEstimator {
  /// Single global calibration scalar from instruction counts to compute units (the original's).
  static let calibrationScale = 5.14816e-12
  /// No estimate is reported above this: a request this big is far past any limit, and the instruction counts
  /// would overflow `Int` long before.
  static let ceiling = 100_000_000
  /// Pixels × images above which the estimate is the ceiling (8192 × 8192 × 8).
  static let sizeGuard = 8192.0 * 8192.0 * 8.0
  /// Images in the batch × (image tokens + reference tokens)² above which the estimate is the ceiling. Attention
  /// grows with the square of the sequence and the heaviest model has about 8·10⁵ instructions per unit of it, so
  /// `Int` overflows near 10¹³; this stays well under.
  static let attentionGuard = 5e12

  /// nil when the family is not covered or the numbers make no sense (spec §6).
  static func estimate(_ inputs: CUInputs) -> Int? {
    guard let family = CUFamily(rawValue: inputs.family), inputs.steps >= 1, inputs.width >= 64, inputs.height >= 64,
      inputs.batchSize >= 1, inputs.strength.isFinite, inputs.guidanceScale.isFinite,
      inputs.imageGuidanceScale.isFinite
    else { return nil }
    let batch = min(inputs.batchSize, 64)
    if Double(inputs.width) * Double(inputs.height) * Double(batch) > sizeGuard { return ceiling }

    let capabilities = inputs.capabilities
    let modifier = CUModifier(key: capabilities.modifier)
    let isGuidanceEmbedEnabled = capabilities.guidanceEmbed && inputs.speedUpWithGuidanceEmbed
    let cfgEnabled =
      !capabilities.isConsistencyModel && !isGuidanceEmbedEnabled
      && isCfgEnabled(
        text: Float(inputs.guidanceScale), image: Float(inputs.imageGuidanceScale), modifier: modifier)
    let cfg = cfgChannels(
      cfgEnabled: cfgEnabled, text: Float(inputs.guidanceScale), image: Float(inputs.imageGuidanceScale),
      modifier: modifier)
    let imageBatch = batch * cfg
    let baseTokenLength = max(1, tokenLength(family: family, padded: capabilities.paddedTextEncodingLength))
    // Draw Things' configuration holds the size in units of 64 pixels; the model starts from `unit × factor`.
    let startWidth = max(1, inputs.width / 64) * startFactor(family)
    let startHeight = max(1, inputs.height / 64) * startFactor(family)
    // The Draw Things app counts one base reference for the models that take references (Kontext and the like)
    // whether or not there is a start image: the user's readings of its CU bar (15 Oct 2026, ReferenceTests) match
    // only so, and the start image moves nothing there. `inputs.hasImage` is therefore not used here.
    let references = referenceImageCount(modifier: modifier, hasImage: true, extra: inputs.referenceImages)
    let imageTokens = max(1, (startHeight / 2) * (startWidth / 2))
    let referenceLength = imageTokens * references
    let sequence = Double(imageTokens) + Double(referenceLength)
    if Double(imageBatch) * sequence * sequence > attentionGuard { return ceiling }

    let counts: (main: Int, fixed: Int)
    switch family {
    case .zImage:
      let main = ZImageInstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, textLength: baseTokenLength, channels: 3840, layers: 30)
      let fixed = ZImageFixedInstructionCount(
        batchSize: 1, timesteps: 1, tokenLength: (baseTokenLength, baseTokenLength), channels: 3840, layers: 30)
      counts = (main * imageBatch, fixed * imageBatch)
    case .qwenImage2_1:
      // The text goes before the image blocks (4096 tokens each); the prefix work is shared across the batch.
      let segments: [(length: Int, image: Bool)] =
        [(baseTokenLength, false)] + Array(repeating: (4096, true), count: references)
      counts = (
        QwenImage2_1InstructionCount(
          batchSize: imageBatch, height: startHeight, width: startWidth,
          prefixLength: baseTokenLength + 4096 * references),
        QwenImage2_1FixedInstructionCount(batchSize: cfg, timesteps: max(1, inputs.steps), segments: segments)
      )
    case .qwenImage:
      let main = QwenImageInstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, textLength: baseTokenLength,
        referenceSequenceLength: referenceLength, channels: 3072, layers: 60,
        isQwenImageLayered: modifier == .qwenimageLayered)
      let fixed = QwenImageFixedInstructionCount(
        timesteps: 1, batchSize: 1, textLength: baseTokenLength, channels: 3072, layers: 60,
        referenceSequenceLength: referenceLength)
      counts = (main * imageBatch, fixed * imageBatch)
    case .ernieImage:
      let main = ErnieImageInstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, textLength: baseTokenLength,
        channels: 4_096, layers: 36, intermediateSize: 12_288)
      let fixed = ErnieImageFixedInstructionCount(batchSize: 1, textLength: baseTokenLength, channels: 4_096)
      counts = (main * imageBatch, fixed * imageBatch)
    case .ideogram4:
      let main = Ideogram4InstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, textLength: baseTokenLength,
        channels: 4_608, layers: 34, intermediateSize: 12_288)
      let fixed = Ideogram4FixedInstructionCount(
        timesteps: 1, batchSize: 1, textLength: baseTokenLength, channels: 4_608, layers: 34)
      counts = (main * imageBatch, fixed * imageBatch)
    case .flux1:
      let main = Flux1InstructionCount(
        batchSize: 1, tokenLength: baseTokenLength, referenceSequenceLength: referenceLength,
        height: startHeight, width: startWidth, channels: 3072, layers: (19, 38), contextPreloaded: true)
      let fixed = Flux1FixedInstructionCount(
        batchSize: (1, 1), tokenLength: baseTokenLength, referenceSequenceLength: referenceLength,
        channels: 3072, layers: (19, 38), contextPreloaded: true, guidanceEmbed: isGuidanceEmbedEnabled)
      counts = (main * imageBatch, fixed * imageBatch)
    case .flux2, .flux2_9b, .flux2_4b:
      let channels: Int
      let layers: (Int, Int)
      if family == .flux2_9b {
        channels = 4096
        layers = (8, 24)
      } else if family == .flux2_4b {
        channels = 3072
        layers = (5, 20)
      } else {
        channels = 6144
        layers = (8, 48)
      }
      let kvCache = modifier == .kontextKv && referenceLength > 0
      let main = Flux2InstructionCount(
        batchSize: 1, tokenLength: baseTokenLength, referenceSequenceLength: kvCache ? 0 : referenceLength,
        cachedReferenceSequenceLength: kvCache ? referenceLength : 0, height: startHeight, width: startWidth,
        channels: channels, layers: layers)
      let fixed = Flux2FixedInstructionCount(
        contextBatchSize: 1, tokenLength: baseTokenLength, timestepCount: kvCache ? 2 : 1,
        referenceSequenceLength: referenceLength, channels: channels, layers: layers,
        guidanceEmbed: isGuidanceEmbedEnabled, kvCache: kvCache)
      counts = (main * imageBatch, fixed * imageBatch)
    case .krea2:
      let fixedTextLength: (Int, Int) = cfg > 1 ? (baseTokenLength, baseTokenLength) : (0, baseTokenLength)
      let totalFixedTextLength = fixedTextLength.0 + fixedTextLength.1
      let main = Krea2InstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, textLength: baseTokenLength,
        hiddenSize: 6_144, layers: 28, intermediateSize: 16_384)
      let textFusion = Krea2TextFusionAdapterInstructionCount(batchSize: 1, textLength: fixedTextLength)
      let fixed = Krea2FixedInstructionCount(batchSize: 1, timesteps: 1, textLength: totalFixedTextLength)
      counts = (main * imageBatch, textFusion + fixed * imageBatch)
    case .sd3, .sd3Large:
      let large = family == .sd3Large
      let dual = large ? [] : capabilities.dualAttentionLayers
      let main = MMDiTInstructionCount(
        batchSize: 1, t: baseTokenLength, height: startHeight, width: startWidth,
        channels: large ? 2432 : 1536, layers: large ? 38 : 24, dualAttentionLayers: dual)
      let fixed = MMDiTFixedInstructionCount(
        batchSize: 1, contextLength: baseTokenLength, channels: large ? 2432 : 1536, layers: large ? 38 : 24,
        dualAttentionLayers: dual)
      counts = (main * imageBatch, fixed * imageBatch)
    case .pixart:
      let lengths = (baseTokenLength, baseTokenLength)
      let main = PixArtInstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, channels: 1152, layers: 28, tokenLength: lengths)
      let fixed = PixArtFixedInstructionCount(batchSize: 1, channels: 1152, layers: 28, tokenLength: lengths)
      counts = (main * imageBatch, fixed * imageBatch)
    case .auraflow:
      let length = max(256, baseTokenLength)
      let main = AuraFlowInstructionCount(
        batchSize: 1, tokenLength: length, height: startHeight, width: startWidth, channels: 3072, layers: (4, 32))
      let fixed = AuraFlowFixedInstructionCount(
        batchSize: (1, 1), tokenLength: length, channels: 3072, layers: (4, 32))
      counts = (main * imageBatch, fixed * imageBatch)
    case .hiDreamI1:
      let width = modifier == .editing ? startWidth * 2 : startWidth
      let main = HiDreamInstructionCount(
        batchSize: 1, height: startHeight, width: width, textLength: (baseTokenLength, baseTokenLength),
        layers: (16, 32))
      let fixed = HiDreamFixedInstructionCount(
        timesteps: 1, layers: (16, 32), t5TextLength: baseTokenLength, llamaTextLength: baseTokenLength)
      counts = (main * imageBatch, fixed * imageBatch)
    case .hiDreamO1:
      let main = HiDreamO1InstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, textLength: baseTokenLength)
      let fixed = HiDreamO1FixedInstructionCount(batchSize: 1, textLength: baseTokenLength)
      counts = (main * imageBatch, fixed * imageBatch)
    case .seedvr2_3b, .seedvr2_7b:
      // SeedVR2's DiT configurations (SeedVR2DiTConfiguration._3B / ._7B) go through the ERNIE count.
      let is7B = family == .seedvr2_7b
      let main = ErnieImageInstructionCount(
        batchSize: 1, height: startHeight, width: startWidth, textLength: baseTokenLength,
        channels: is7B ? 3_072 : 2_560, layers: is7B ? 36 : 32, intermediateSize: is7B ? 12_288 : 6_912)
      counts = (main * imageBatch, 0)
    }

    let strength = Double(max(Float(inputs.strength), 0.05))
    let main = Double(counts.main) * calibrationScale * Double(inputs.steps) * strength
    let fixed = Double(counts.fixed) * calibrationScale
    let total = (main + fixed) * usageBias(family)
    guard total.isFinite, total > 0 else { return nil }
    return Int(min(Double(ceiling), total.rounded(.up)))
  }

  /// The multiplier that steers usage toward preferred models: 1 for every family covered here.
  static func usageBias(_ family: CUFamily) -> Double { 1.0 }

  /// The factor between the size in units of 64 pixels and the model's start size (`modelStartSizeFromConfiguration`).
  static func startFactor(_ family: CUFamily) -> Int {
    switch family {
    case .qwenImage2_1: return 4
    case .hiDreamO1: return 2
    default: return 8
    }
  }

  /// The padded text length of the model's spec, or the family's default (`defaultTokenLength`).
  static func tokenLength(family: CUFamily, padded: Int) -> Int {
    if padded > 0 { return padded }
    switch family {
    case .zImage, .qwenImage, .qwenImage2_1, .ernieImage, .ideogram4, .flux1, .flux2, .flux2_9b, .flux2_4b:
      return 512
    case .krea2: return 256
    case .hiDreamI1: return 128
    case .sd3, .sd3Large, .pixart, .auraflow, .hiDreamO1: return 77
    case .seedvr2_3b, .seedvr2_7b: return 77
    }
  }

  /// `referenceImageCount` of the original: pictures that go with the request through the model's modifier.
  static func referenceImageCount(modifier: CUModifier, hasImage: Bool, extra: Int) -> Int {
    let base = hasImage ? 1 : 0
    let more = max(0, extra)
    switch modifier {
    case .qwenimageLayered: return base
    case .kontext, .kontextKv, .qwenimageEditPlus, .qwenimageEdit2511, .ref2va: return base + more
    case .fl2va: return hasImage ? 1 + min(more, 1) : 0
    default: return 0
    }
  }

  // MARK: CFG (Sampler.swift)

  static func isCfgEnabled(text: Float, image: Float, modifier: CUModifier) -> Bool {
    if modifier == .editing {
      return !((text - 1).magnitude <= 1e-3 && (image - 1).magnitude <= 1e-3)
    }
    return (text - 1).magnitude > 1e-3
  }

  static func cfgChannels(cfgEnabled: Bool, text: Float, image: Float, modifier: CUModifier) -> Int {
    switch modifier {
    case .editing:
      guard cfgEnabled else { return 1 }
      return (text - image).magnitude <= 1e-3 ? 2 : 3
    default:
      return cfgEnabled ? 2 : 1
    }
  }
}
