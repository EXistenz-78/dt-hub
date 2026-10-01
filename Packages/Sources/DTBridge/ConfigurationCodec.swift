import DrawThingsClient
import Foundation
import HubKit

/// The Draw Things configuration JSON (spec §6, level 3) on top of DrawThingsConfiguration:
/// export, validation, and applying a complete or partial text to DT Hub's parameters.
public struct DrawThingsConfigurationCodec: ConfigurationCodec {
  public init() {}

  public func exportJSON(_ state: ConfigurationState) -> String {
    var configuration = JobMapper.configuration(model: state.model, parameters: state.parameters)
    if state.parameters.randomSeed { configuration.seed = nil }
    return (try? configuration.toJSON()) ?? "{}"
  }

  /// The message is the library's (or ours), in English: a technical detail the interface
  /// shows under its own localized headline.
  public func validate(_ json: String) -> String? {
    let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)), object is [String: Any] || trimmed.isEmpty else {
      return trimmed.isEmpty ? nil : "The text must be a JSON object, like {\"steps\": 8}"
    }
    return DrawThingsConfiguration.validateJSON(json).error
  }

  /// The top-level keys of `json` that are not Draw Things settings (typos, newer versions):
  /// they are ignored.
  public func unknownKeys(in json: String) -> [String] {
    guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
    return object.keys.filter { !Self.knownKeys.contains($0) }.sorted()
  }

  public func apply(json: String, to state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState {
    if let error = validate(json) { throw ConfigurationError(error) }
    var configuration = JobMapper.configuration(model: state.model, parameters: state.parameters)
    configuration.seed = state.parameters.randomSeed ? nil : state.parameters.seed
    do {
      try configuration.mergeJSON(json)
      try configuration.validate()
    } catch {
      throw ConfigurationError(error.localizedDescription)
    }
    var parameters = Self.parameters(from: configuration, base: state.parameters)
    if let overlay = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] {
      for (key, value) in overlay where Self.extraKeys.contains(key) {
        // A value equal to Draw Things' default is no setting at all: a complete export
        // would otherwise fill `extra` with every default.
        if let standard = Self.defaults[key], (standard as AnyObject).isEqual(value) {
          parameters.extra[key] = nil
        } else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
          let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        {
          parameters.extra[key] = decoded
        }
      }
    }
    return ConfigurationState(model: configuration.model, parameters: parameters.clamped())
  }

  // MARK: Keys

  /// The keys DT Hub has a card or field for.
  static let modeledKeys: Set<String> = [
    "width", "height", "steps", "model", "sampler", "guidanceScale", "seed", "shift",
    "resolutionDependentShift", "cfgZeroStar", "cfgZeroInitSteps", "batchCount", "batchSize", "loras",
    "refinerModel", "refinerStart", "hiresFix", "hiresFixWidth", "hiresFixHeight", "hiresFixStrength",
    "upscaler", "upscalerScaleFactor", "faceRestoration", "guidanceEmbed", "speedUpWithGuidanceEmbed",
    "sharpness", "stochasticSamplingGamma", "clipSkip", "t5TextEncoder", "separateClipL", "clipLText",
    "separateOpenClipG", "openClipGText", "separateT5", "t5Text", "zeroNegativePrompt", "aestheticScore",
    "negativeAestheticScore", "cropTop", "cropLeft", "originalImageWidth", "originalImageHeight",
    "targetImageWidth", "targetImageHeight", "negativeOriginalImageWidth", "negativeOriginalImageHeight",
    "tiledDecoding", "decodingTileWidth", "decodingTileHeight", "decodingTileOverlap", "tiledDiffusion",
    "diffusionTileWidth", "diffusionTileHeight", "diffusionTileOverlap", "teaCache", "teaCacheStart",
    "teaCacheEnd", "teaCacheThreshold", "teaCacheMaxSkipSteps", "colorCalibration", "compressionArtifacts",
    "compressionArtifactsQuality",
  ]

  /// Keys that identify the configuration, not a setting.
  static let ignoredKeys: Set<String> = ["id", "name"]

  /// A complete export of the library's default configuration. Built once and never changed
  /// (hence `nonisolated(unsafe)`: `Any` is not `Sendable`).
  nonisolated(unsafe) static let defaults: [String: Any] = {
    let json = (try? DrawThingsConfiguration().toJSON()) ?? "{}"
    return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
  }()

  /// Every key Draw Things writes: the defaults' keys and those written only when set.
  static let knownKeys: Set<String> = Set(defaults.keys).union(["enableInpainting", "name", "id", "t5Text"])

  /// Settings with no card: kept in `GenerationParameters.extra`.
  static var extraKeys: Set<String> { knownKeys.subtracting(modeledKeys).subtracting(ignoredKeys) }

  // MARK: Mapping back

  /// The parameters a configuration describes, with `base` supplying what the JSON does not
  /// carry: the LoRA trigger words, the extra settings.
  static func parameters(from c: DrawThingsConfiguration, base: GenerationParameters) -> GenerationParameters {
    func d(_ value: Float) -> Double { Double("\(value)") ?? Double(value) }
    var p = base
    p.width = Int(c.width)
    p.height = Int(c.height)
    p.steps = Int(c.steps)
    p.guidanceScale = d(c.guidanceScale)
    p.cfgZeroStar = c.cfgZeroStar
    p.cfgZeroInitSteps = Int(c.cfgZeroInitSteps)
    p.sampler = Sampler(rawValue: Int(c.sampler.rawValue)) ?? base.sampler
    p.shift = d(c.shift)
    p.resolutionDependentShift = c.resolutionDependentShift
    p.randomSeed = c.seed == nil
    p.seed = c.seed ?? base.seed
    p.batchSize = Int(c.batchSize)
    p.batchCount = Int(c.batchCount)
    p.loras = c.loras.map { lora in
      LoRASelection(
        file: lora.file, weight: d(lora.weight), mode: HubKit.LoRAMode(rawValue: Int(lora.mode.rawValue)) ?? .all,
        trigger: base.loras.first { $0.file == lora.file }?.trigger ?? "")
    }
    var a = AdvancedParameters()
    a.refinerModel = c.refinerModel ?? ""
    a.refinerStart = d(c.refinerStart)
    a.hiresFix = c.hiresFix
    a.hiresFixWidth = Int(c.hiresFixWidth)
    a.hiresFixHeight = Int(c.hiresFixHeight)
    a.hiresFixStrength = d(c.hiresFixStrength)
    a.upscaler = c.upscaler ?? ""
    a.upscalerScaleFactor = Int(c.upscalerScaleFactor)
    a.faceRestoration = c.faceRestoration ?? ""
    a.guidanceEmbed = d(c.guidanceEmbed)
    a.speedUpWithGuidanceEmbed = c.speedUpWithGuidanceEmbed
    a.sharpness = d(c.sharpness)
    a.stochasticSamplingGamma = d(c.stochasticSamplingGamma)
    a.clipSkip = Int(c.clipSkip)
    a.t5TextEncoder = c.t5TextEncoder
    a.separateClipL = c.separateClipL
    a.clipLText = c.clipLText ?? ""
    a.separateOpenClipG = c.separateOpenClipG
    a.openClipGText = c.openClipGText ?? ""
    a.separateT5 = c.separateT5
    a.t5Text = c.t5Text ?? ""
    a.zeroNegativePrompt = c.zeroNegativePrompt
    a.aestheticScore = d(c.aestheticScore)
    a.negativeAestheticScore = d(c.negativeAestheticScore)
    a.cropTop = Int(c.cropTop)
    a.cropLeft = Int(c.cropLeft)
    a.originalWidth = Int(c.originalImageWidth)
    a.originalHeight = Int(c.originalImageHeight)
    a.targetWidth = Int(c.targetImageWidth)
    a.targetHeight = Int(c.targetImageHeight)
    a.negativeOriginalWidth = Int(c.negativeOriginalImageWidth)
    a.negativeOriginalHeight = Int(c.negativeOriginalImageHeight)
    a.tiledDecoding = c.tiledDecoding
    a.decodingTileWidth = Int(c.decodingTileWidth)
    a.decodingTileHeight = Int(c.decodingTileHeight)
    a.decodingTileOverlap = Int(c.decodingTileOverlap)
    a.tiledDiffusion = c.tiledDiffusion
    a.diffusionTileWidth = Int(c.diffusionTileWidth)
    a.diffusionTileHeight = Int(c.diffusionTileHeight)
    a.diffusionTileOverlap = Int(c.diffusionTileOverlap)
    a.teaCache = c.teaCache
    a.teaCacheStart = Int(c.teaCacheStart)
    a.teaCacheEnd = Int(c.teaCacheEnd)
    a.teaCacheThreshold = d(c.teaCacheThreshold)
    a.teaCacheMaxSkipSteps = Int(c.teaCacheMaxSkipSteps)
    a.colorCalibration = c.colorCalibration != .disabled
    a.compressionArtifacts = CompressionArtifacts(rawValue: Int(c.compressionArtifacts.rawValue)) ?? .none
    a.compressionQuality = d(c.compressionArtifactsQuality)
    p.advanced = a
    return p
  }
}
