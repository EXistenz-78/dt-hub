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
  public func validate(_ json: String, for state: ConfigurationState) -> String? {
    do {
      _ = try resolve(json, state)
      return nil
    } catch {
      return error.message
    }
  }

  /// The top-level keys of `json` that are not Draw Things settings (typos, newer versions):
  /// they are ignored.
  public func unknownKeys(in json: String) -> [String] {
    guard let object = try? JSONSerialization.jsonObject(with: Data(Self.normalized(json).utf8)) as? [String: Any]
    else { return [] }
    return object.keys.filter { !Self.knownKeys.contains($0) }.sorted()
  }

  public func apply(json: String, to state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState {
    try resolve(json, state)
  }

  /// A neutral model name for a tab with none chosen: the library wants one, DT Hub does not.
  private static let noModel = "-"

  /// Straight quotes for the curly ones the Mac types when "smart quotes" is on.
  static func normalized(_ json: String) -> String {
    json.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
      .replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
  }

  /// The text applied to the state, or why it cannot be: syntax, the library's own checks
  /// (a Hires fix size of 0 and no model are DT Hub's "automatic" and "none", not errors),
  /// then the ranges DT Hub allows, which must not be quietly clamped.
  private func resolve(_ text: String, _ state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState {
    let json = Self.normalized(text)
    let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
    var overlay: [String: Any] = [:]
    if !trimmed.isEmpty {
      let parsed: Any
      do {
        parsed = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
      } catch {
        throw ConfigurationError("Invalid JSON: \((error as NSError).localizedDescription)")
      }
      guard let object = parsed as? [String: Any] else {
        throw ConfigurationError("The text must be a JSON object, like {\"steps\": 8}")
      }
      overlay = object
    }
    var configuration = JobMapper.configuration(
      model: state.model.isEmpty ? Self.noModel : state.model, parameters: state.parameters)
    configuration.seed = state.parameters.randomSeed ? nil : state.parameters.seed
    do {
      // An empty model is DT Hub's "none" (an export of a tab with no model has one).
      var mergeable = overlay
      if (mergeable["model"] as? String)?.isEmpty == true { mergeable["model"] = nil }
      if mergeable.isEmpty {
        try configuration.mergeJSON("{}")
      } else {
        try configuration.mergeJSON(String(decoding: try JSONSerialization.data(withJSONObject: mergeable), as: UTF8.self))
      }
      var checked = configuration
      if checked.hiresFix {
        if checked.hiresFixWidth == 0 { checked.hiresFixWidth = 64 }
        if checked.hiresFixHeight == 0 { checked.hiresFixHeight = 64 }
      }
      try checked.validate()
    } catch {
      throw ConfigurationError(error.localizedDescription)
    }
    var parameters = Self.parameters(from: configuration, base: state.parameters)
    if let problem = Self.rangeProblem(parameters) { throw ConfigurationError(problem) }
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
    let model = configuration.model == Self.noModel ? "" : configuration.model
    return ConfigurationState(model: model, parameters: parameters.clamped())
  }

  /// The first value that DT Hub would clamp: out of its range, not just off the 64 grid.
  /// Sizes within half a step of a multiple of 64 are only rounded later.
  static func rangeProblem(_ parameters: GenerationParameters) -> String? {
    guard let before = try? encode(parameters), let after = try? encode(parameters.clamped()) else { return nil }
    return firstDifference(before, after, path: "")
  }

  private static func encode(_ parameters: GenerationParameters) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(parameters))
  }

  private static func firstDifference(_ a: JSONValue, _ b: JSONValue, path: String) -> String? {
    switch (a, b) {
    case (.object(let x), .object(let y)):
      for key in x.keys.sorted() {
        let child = path.isEmpty ? key : "\(path).\(key)"
        if let found = firstDifference(x[key] ?? .null, y[key] ?? .null, path: child) { return found }
      }
      return nil
    case (.array(let x), .array(let y)) where x.count == y.count:
      for index in x.indices {
        if let found = firstDifference(x[index], y[index], path: "\(path)[\(index)]") { return found }
      }
      return nil
    default:
      guard a != b else { return nil }
      guard let x = number(a), let y = number(b) else { return "\(path) is not valid" }
      let name = path.split(separator: ".").last.map(String.init)?.lowercased() ?? path
      if name.hasSuffix("width") || name.hasSuffix("height"), abs(x - y) < 32 { return nil }
      return "\(path) is out of range (got \(format(x)); the nearest allowed value is \(format(y)))"
    }
  }

  private static func number(_ value: JSONValue) -> Double? {
    switch value {
    case .int(let n): Double(n)
    case .double(let n): n
    default: nil
    }
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
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
    // A text is sent only with its switch on: with it off the card's text is kept.
    a.clipLText = c.clipLText ?? (c.separateClipL ? "" : base.advanced.clipLText)
    a.separateOpenClipG = c.separateOpenClipG
    // A text is sent only with its switch on: with it off the card's text is kept.
    a.openClipGText = c.openClipGText ?? (c.separateOpenClipG ? "" : base.advanced.openClipGText)
    a.separateT5 = c.separateT5
    // A text is sent only with its switch on: with it off the card's text is kept.
    a.t5Text = c.t5Text ?? (c.separateT5 ? "" : base.advanced.t5Text)
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
