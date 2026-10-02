import CoreGraphics
import DrawThingsClient
import HubKit

/// Translates DT Hub's `GenerationJob` and the library's events (spec §5).
enum JobMapper {
  /// A text-to-image request (no Control tab images).
  static func request(for job: GenerationJob) -> GenerationRequest {
    GenerationRequest(
      prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
      configuration: configuration(model: job.model, parameters: job.parameters))
  }

  /// The request with the Control tab's images: the start image (and its strength), and the
  /// Moodboard as one "shuffle" hint whose weights are the pictures' shares. A picture the library
  /// cannot read stops the RUN with a message.
  static func request(for job: GenerationJob, inputs: GenerationInputs) throws -> GenerationRequest {
    var configuration = configuration(model: job.model, parameters: job.parameters)
    // The start image and its strength come from the Control tab, after the JSON editor's
    // extra settings: they win. Without an image the RUN stays text-to-image.
    if inputs.image != nil, let strength = job.imageStrength { configuration.strength = Float(strength) }
    // The mask needs an image under it; Draw Things regenerates the transparent pixels.
    var mask: CGImage?
    if let drawn = inputs.mask, inputs.image != nil {
      let settings = (job.maskSettings ?? MaskSettings()).clamped()
      configuration.maskBlur = Float(settings.blur)
      configuration.maskBlurOutset = Int32(settings.outset)
      configuration.preserveOriginalAfterInpaint = settings.preserveOriginal
      configuration.enableInpainting = inputs.enableInpainting
      mask = drawn
    }
    var hints = HintBuilder()
    for hint in inputs.hints { hints.addMoodboardImage(hint.imageData, weight: Float(hint.weight)) }
    let built: [HintProto]
    do {
      built = try hints.build()
    } catch {
      throw BackendError.generationFailed(error.localizedDescription)
    }
    return GenerationRequest(
      prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
      configuration: configuration, image: inputs.image, mask: mask, hints: built)
  }

  /// The Draw Things configuration for a model and parameters: clamped, the Advanced cards
  /// applied, then the JSON editor's extra settings on top.
  static func configuration(model: String, parameters unclamped: GenerationParameters) -> DrawThingsConfiguration {
    let parameters = unclamped.clamped()
    var configuration = DrawThingsConfiguration(
      width: Int32(parameters.width),
      height: Int32(parameters.height),
      steps: Int32(parameters.steps),
      model: model,
      sampler: SamplerType(rawValue: Int8(parameters.sampler.rawValue)) ?? .unipctrailing,
      guidanceScale: Float(parameters.guidanceScale),
      seed: parameters.seed,
      shift: Float(parameters.shift),
      batchCount: Int32(parameters.batchCount),
      batchSize: Int32(parameters.batchSize),
      cfgZeroStar: parameters.cfgZeroStar,
      cfgZeroInitSteps: Int32(parameters.cfgZeroInitSteps),
      resolutionDependentShift: parameters.resolutionDependentShift)
    // HubKit and the library both have a `LoRAMode`: the library's is qualified.
    configuration.loras = parameters.loras.map {
      LoRAConfig(
        file: $0.file, weight: Float($0.weight),
        mode: DrawThingsClient.LoRAMode(rawValue: Int8($0.mode.rawValue)) ?? .all)
    }
    apply(parameters.advanced, to: &configuration)
    // The extra settings are keys of the configuration JSON the cards do not cover; a text
    // the library cannot take is left out rather than stopping the RUN.
    if let extra = JSONValue.text(of: parameters.extra) { try? configuration.mergeJSON(extra) }
    return configuration
  }

  /// The Advanced cards' values; "" names become nil ("none"), a separate text is sent only
  /// with its switch on.
  static func apply(_ advanced: AdvancedParameters, to configuration: inout DrawThingsConfiguration) {
    func name(_ file: String) -> String? { file.isEmpty ? nil : file }
    configuration.refinerModel = name(advanced.refinerModel)
    configuration.refinerStart = Float(advanced.refinerStart)
    configuration.hiresFix = advanced.hiresFix
    configuration.hiresFixWidth = Int32(advanced.hiresFixWidth)
    configuration.hiresFixHeight = Int32(advanced.hiresFixHeight)
    configuration.hiresFixStrength = Float(advanced.hiresFixStrength)
    configuration.upscaler = name(advanced.upscaler)
    configuration.upscalerScaleFactor = Int32(advanced.upscalerScaleFactor)
    configuration.faceRestoration = name(advanced.faceRestoration)
    configuration.guidanceEmbed = Float(advanced.guidanceEmbed)
    configuration.speedUpWithGuidanceEmbed = advanced.speedUpWithGuidanceEmbed
    configuration.sharpness = Float(advanced.sharpness)
    configuration.stochasticSamplingGamma = Float(advanced.stochasticSamplingGamma)
    configuration.clipSkip = Int32(advanced.clipSkip)
    configuration.t5TextEncoder = advanced.t5TextEncoder
    configuration.separateClipL = advanced.separateClipL
    configuration.clipLText = advanced.separateClipL ? advanced.clipLText : nil
    configuration.separateOpenClipG = advanced.separateOpenClipG
    configuration.openClipGText = advanced.separateOpenClipG ? advanced.openClipGText : nil
    configuration.separateT5 = advanced.separateT5
    configuration.t5Text = advanced.separateT5 ? advanced.t5Text : nil
    configuration.zeroNegativePrompt = advanced.zeroNegativePrompt
    configuration.aestheticScore = Float(advanced.aestheticScore)
    configuration.negativeAestheticScore = Float(advanced.negativeAestheticScore)
    configuration.cropTop = Int32(advanced.cropTop)
    configuration.cropLeft = Int32(advanced.cropLeft)
    configuration.originalImageWidth = Int32(advanced.originalWidth)
    configuration.originalImageHeight = Int32(advanced.originalHeight)
    configuration.targetImageWidth = Int32(advanced.targetWidth)
    configuration.targetImageHeight = Int32(advanced.targetHeight)
    configuration.negativeOriginalImageWidth = Int32(advanced.negativeOriginalWidth)
    configuration.negativeOriginalImageHeight = Int32(advanced.negativeOriginalHeight)
    configuration.tiledDecoding = advanced.tiledDecoding
    configuration.decodingTileWidth = Int32(advanced.decodingTileWidth)
    configuration.decodingTileHeight = Int32(advanced.decodingTileHeight)
    configuration.decodingTileOverlap = Int32(advanced.decodingTileOverlap)
    configuration.tiledDiffusion = advanced.tiledDiffusion
    configuration.diffusionTileWidth = Int32(advanced.diffusionTileWidth)
    configuration.diffusionTileHeight = Int32(advanced.diffusionTileHeight)
    configuration.diffusionTileOverlap = Int32(advanced.diffusionTileOverlap)
    configuration.teaCache = advanced.teaCache
    configuration.teaCacheStart = Int32(advanced.teaCacheStart)
    configuration.teaCacheEnd = Int32(advanced.teaCacheEnd)
    configuration.teaCacheThreshold = Float(advanced.teaCacheThreshold)
    configuration.teaCacheMaxSkipSteps = Int32(advanced.teaCacheMaxSkipSteps)
    configuration.colorCalibration = advanced.colorCalibration ? .lab : .disabled
    configuration.compressionArtifacts = CompressionMethod(rawValue: Int8(advanced.compressionArtifacts.rawValue)) ?? .disabled
    configuration.compressionArtifactsQuality = Float(advanced.compressionQuality)
  }

  /// The update for a library event; nil for events DT Hub does not show (audio, downloads,
  /// single images: the batch's full list arrives with `.completed`).
  static func update(for event: GenerationEvent) throws -> GenerationUpdate? {
    switch event {
    case .progress(let progress):
      switch progress.stage {
      case .sampling(let step), .secondPassSampling(let step):
        return .progress(step: step, totalSteps: progress.totalSteps)
      default:
        break
      }
      return .progress(step: nil, totalSteps: progress.totalSteps)
    case .preview(let image):
      return .preview(image)
    case .completed(let result):
      guard !result.images.isEmpty else { throw BackendError.noImages }
      return .finished(result.images)
    case .image, .audio, .remoteDownload:
      return nil
    }
  }

  /// A library error as DT Hub reports it; cancellation passes through unchanged.
  static func backendError(for error: any Error) -> any Error {
    if error is CancellationError || error is BackendError { return error }
    if case DrawThingsError.connectionFailed(let detail) = error { return BackendError.unreachable(detail) }
    if case DrawThingsError.unauthenticated = error { return BackendError.unauthorized }
    // The library reports a RUN that ends without images (e.g. #131) this way.
    if case DrawThingsError.incompleteResponse(let detail) = error, detail.contains("without returning an image") {
      return BackendError.noImages
    }
    return BackendError.generationFailed(error.localizedDescription)
  }
}
