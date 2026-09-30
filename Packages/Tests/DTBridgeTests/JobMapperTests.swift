import DrawThingsClient
import HubKit
import Testing

@testable import DTBridge

struct JobMapperTests {
  @Test func mapsEveryBaseParameter() {
    let parameters = GenerationParameters(
      width: 832, height: 1216, steps: 4, guidanceScale: 1.5, cfgZeroStar: true, cfgZeroInitSteps: 2,
      sampler: .ddimTrailing, shift: 2, resolutionDependentShift: false,
      seed: 42, randomSeed: false, batchSize: 2, batchCount: 3)
    let request = JobMapper.request(
      for: GenerationJob(prompt: "a lighthouse", model: "flux_2_klein_9b_f16.ckpt", parameters: parameters))
    let configuration = request.configuration
    #expect(request.prompt == "a lighthouse")
    #expect(configuration.model == "flux_2_klein_9b_f16.ckpt")
    #expect(configuration.width == 832)
    #expect(configuration.height == 1216)
    #expect(configuration.steps == 4)
    #expect(configuration.guidanceScale == 1.5)
    #expect(configuration.sampler == .ddimtrailing)
    #expect(configuration.shift == 2)
    #expect(configuration.seed == 42)
    #expect(configuration.batchSize == 2)
    #expect(configuration.batchCount == 3)
    #expect(configuration.cfgZeroStar)
    #expect(configuration.cfgZeroInitSteps == 2)
    #expect(!configuration.resolutionDependentShift)
  }

  @Test func sendsTheNegativePromptAndTheLoRAs() {
    let parameters = GenerationParameters(loras: [
      LoRASelection(file: "style.safetensors", weight: 0.75, mode: .base), LoRASelection(file: "detail.safetensors"),
    ])
    let request = JobMapper.request(
      for: GenerationJob(prompt: "a fox", negativePrompt: "blurry", model: "m.ckpt", parameters: parameters))
    #expect(request.prompt == "a fox")
    #expect(request.negativePrompt == "blurry")
    #expect(request.configuration.loras == [
      LoRAConfig(file: "style.safetensors", weight: 0.75, mode: .base),
      LoRAConfig(file: "detail.safetensors", weight: 1, mode: .all),
    ])
  }

  @Test func triggerWordsArePutInFrontOfThePrompt() {
    let parameters = GenerationParameters(loras: [LoRASelection(file: "tarot.safetensors", trigger: "vintage tarot style")])
    let request = JobMapper.request(for: GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: parameters))
    #expect(request.prompt == "vintage tarot style a fox")
  }

  @Test func sendsTheAdvancedValues() {
    var advanced = AdvancedParameters()
    advanced.refinerModel = "refiner.ckpt"
    advanced.refinerStart = 0.6
    advanced.hiresFix = true
    advanced.hiresFixWidth = 512
    advanced.hiresFixHeight = 768
    advanced.upscaler = "realesrgan_x4plus_f16.ckpt"
    advanced.upscalerScaleFactor = 2
    advanced.guidanceEmbed = 4.5
    advanced.clipSkip = 2
    advanced.separateT5 = true
    advanced.t5Text = "long text"
    advanced.clipLText = "ignored without its switch"
    advanced.aestheticScore = 7
    advanced.tiledDecoding = true
    advanced.teaCache = true
    advanced.teaCacheThreshold = 0.2
    advanced.colorCalibration = true
    advanced.compressionArtifacts = .jpeg
    advanced.compressionQuality = 60
    let configuration = JobMapper.request(
      for: GenerationJob(prompt: "p", model: "m.ckpt", parameters: GenerationParameters(width: 1024, height: 1024, advanced: advanced))
    ).configuration
    #expect(configuration.refinerModel == "refiner.ckpt")
    #expect(abs(configuration.refinerStart - 0.6) < 0.0001)
    #expect(configuration.hiresFix)
    #expect(configuration.hiresFixWidth == 512)
    #expect(configuration.hiresFixHeight == 768)
    #expect(configuration.upscaler == "realesrgan_x4plus_f16.ckpt")
    #expect(configuration.upscalerScaleFactor == 2)
    #expect(configuration.faceRestoration == nil)
    #expect(configuration.guidanceEmbed == 4.5)
    #expect(configuration.clipSkip == 2)
    #expect(configuration.separateT5)
    #expect(configuration.t5Text == "long text")
    #expect(configuration.clipLText == nil)
    #expect(configuration.aestheticScore == 7)
    #expect(configuration.tiledDecoding)
    #expect(configuration.teaCache)
    #expect(abs(configuration.teaCacheThreshold - 0.2) < 0.0001)
    #expect(configuration.colorCalibration == .lab)
    #expect(configuration.compressionArtifacts == .jpeg)
    #expect(configuration.compressionArtifactsQuality == 60)
  }

  @Test func defaultAdvancedValuesMatchTheLibrarysDefaults() {
    let sent = JobMapper.request(for: GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default)).configuration
    let library = DrawThingsConfiguration()
    #expect(sent.refinerModel == library.refinerModel)
    #expect(sent.refinerStart == library.refinerStart)
    #expect(sent.hiresFix == library.hiresFix)
    #expect(sent.hiresFixStrength == library.hiresFixStrength)
    #expect(sent.upscaler == library.upscaler)
    #expect(sent.guidanceEmbed == library.guidanceEmbed)
    #expect(sent.speedUpWithGuidanceEmbed == library.speedUpWithGuidanceEmbed)
    #expect(sent.sharpness == library.sharpness)
    #expect(sent.stochasticSamplingGamma == library.stochasticSamplingGamma)
    #expect(sent.clipSkip == library.clipSkip)
    #expect(sent.t5TextEncoder == library.t5TextEncoder)
    #expect(sent.aestheticScore == library.aestheticScore)
    #expect(sent.negativeAestheticScore == library.negativeAestheticScore)
    #expect(sent.decodingTileWidth == library.decodingTileWidth)
    #expect(sent.diffusionTileOverlap == library.diffusionTileOverlap)
    #expect(sent.teaCacheStart == library.teaCacheStart)
    #expect(sent.teaCacheEnd == library.teaCacheEnd)
    #expect(sent.teaCacheThreshold == library.teaCacheThreshold)
    #expect(sent.teaCacheMaxSkipSteps == library.teaCacheMaxSkipSteps)
    #expect(sent.colorCalibration == library.colorCalibration)
    #expect(sent.compressionArtifacts == library.compressionArtifacts)
    #expect(sent.compressionArtifactsQuality == library.compressionArtifactsQuality)
  }

  @Test func clampsOutOfRangeValuesBeforeSending() {
    let parameters = GenerationParameters(width: 1000, height: 5000, steps: 0, batchSize: 9)
    let configuration = JobMapper.request(
      for: GenerationJob(prompt: "", model: "m.ckpt", parameters: parameters)
    ).configuration
    #expect(configuration.width == 1024)
    #expect(configuration.height == 2048)
    #expect(configuration.steps == 1)
    #expect(configuration.batchSize == 4)
  }

  @Test func samplingProgressCarriesTheStep() throws {
    let update = try JobMapper.update(for: .progress(GenerationProgress(stage: .sampling(step: 3), totalSteps: 8)))
    guard case .progress(let step, let total)? = update else { Issue.record("not progress"); return }
    #expect(step == 3)
    #expect(total == 8)
  }

  @Test func otherStagesHaveNoStep() throws {
    let update = try JobMapper.update(for: .progress(GenerationProgress(stage: .textEncoding, totalSteps: 8)))
    guard case .progress(let step, _)? = update else { Issue.record("not progress"); return }
    #expect(step == nil)
  }

  @Test func secondPassSamplingCarriesTheStep() throws {
    let update = try JobMapper.update(for: .progress(GenerationProgress(stage: .secondPassSampling(step: 2), totalSteps: 8)))
    guard case .progress(let step, _)? = update else { Issue.record("not progress"); return }
    #expect(step == 2)
  }

  @Test func aServerThatFinishesWithoutAnImageMeansNoImages() {
    let error = DrawThingsError.incompleteResponse("the server finished without returning an image; check the server log")
    #expect(JobMapper.backendError(for: error) as? BackendError == .noImages)
    let broken = DrawThingsError.incompleteResponse("the stream ended in the middle of a chunked tensor")
    #expect(JobMapper.backendError(for: broken) as? BackendError != .noImages)
  }

  @Test func libraryErrorsBecomeBackendErrors() {
    #expect(JobMapper.backendError(for: DrawThingsError.connectionFailed("down")) as? BackendError == .unreachable("down"))
    #expect(JobMapper.backendError(for: DrawThingsError.unauthenticated) as? BackendError == .unauthorized)
    #expect(JobMapper.backendError(for: CancellationError()) is CancellationError)
  }
}
