import DrawThingsClient
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

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

  @Test func sendsTheStartImageAndItsStrength() throws {
    let image = try #require(TestImages.make(width: 64, height: 48))
    var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
    job.imageStrength = 0.6
    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image))
    #expect(request.image === image)
    #expect(abs(request.configuration.strength - 0.6) < 0.0001)
    // The Control tab's strength wins over a "strength" key of the JSON editor.
    var withExtra = job
    withExtra = GenerationJob(
      prompt: "a fox", model: "m.ckpt",
      parameters: GenerationParameters(extra: ["strength": .double(0.2)]), imageStrength: 0.6)
    let wins = try JobMapper.request(for: withExtra, inputs: GenerationInputs(image: image))
    #expect(abs(wins.configuration.strength - 0.6) < 0.0001)
  }

  @Test func withoutAnImageTheRequestIsTextToImage() throws {
    var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: .default)
    job.imageStrength = 0.6
    let request = try JobMapper.request(for: job, inputs: .none)
    #expect(request.image == nil)
    #expect(request.configuration.strength == 1.0)
    #expect(JobMapper.request(for: job).image == nil)
  }

  func pngBytes(width: Int = 32, height: Int = 24) throws -> Data {
    let image = try #require(TestImages.make(width: width, height: height))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  @Test func sendsTheMoodboardAsOneShuffleHintWithTheSharesAsWeights() throws {
    let bytes = try pngBytes()
    let inputs = GenerationInputs(hints: [
      GenerationHint(imageData: bytes, weight: 0.7), GenerationHint(imageData: bytes, weight: 0.3),
    ])
    let request = try JobMapper.request(
      for: GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: .default), inputs: inputs)
    #expect(request.image == nil)
    #expect(request.hints.count == 1)
    #expect(request.hints[0].hintType == "shuffle")
    #expect(request.hints[0].tensors.count == 2)
    #expect(abs(request.hints[0].tensors[0].weight - 0.7) < 0.0001)
    #expect(abs(request.hints[0].tensors[1].weight - 0.3) < 0.0001)
  }

  @Test func aStartImageAndAMoodboardGoTogetherAndNoHintsMeansNone() throws {
    let image = try #require(TestImages.make(width: 64, height: 64))
    let job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
    let both = try JobMapper.request(
      for: job, inputs: GenerationInputs(image: image, hints: [GenerationHint(imageData: try pngBytes(), weight: 1)]))
    #expect(both.image === image && both.hints.count == 1)
    #expect(try JobMapper.request(for: job, inputs: GenerationInputs(image: image)).hints.isEmpty)
  }

  @Test func aHintThatCannotBeReadStopsTheRunWithAMessage() {
    let inputs = GenerationInputs(hints: [GenerationHint(imageData: Data([1, 2, 3]), weight: 1)])
    #expect(throws: BackendError.self) {
      try JobMapper.request(for: GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default), inputs: inputs)
    }
  }

  @Test func sendsTheMaskWithItsSettings() throws {
    let image = try #require(TestImages.make(width: 64, height: 48))
    let mask = try #require(TestImages.make(width: 64, height: 48))
    var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 48))
    job.imageStrength = 1
    job.maskSettings = MaskSettings(blur: 4, outset: 12, preserveOriginal: false)
    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
    #expect(request.mask === mask)
    #expect(request.configuration.maskBlur == 4)
    #expect(request.configuration.maskBlurOutset == 12)
    #expect(!request.configuration.preserveOriginalAfterInpaint)
    // No inpaint control unless the model needs it.
    #expect(!request.configuration.enableInpainting)
    let control = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask, enableInpainting: true))
    #expect(control.configuration.enableInpainting)
  }

  @Test func aMaskWithoutSettingsGetsDrawThingsDefaults() throws {
    let image = try #require(TestImages.make(width: 32, height: 32))
    let mask = try #require(TestImages.make(width: 32, height: 32))
    let job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
    #expect(request.configuration.maskBlur == 1.5)
    #expect(request.configuration.maskBlurOutset == 0)
    #expect(request.configuration.preserveOriginalAfterInpaint)
  }

  @Test func aMaskWithoutAnImageIsNotSent() throws {
    let mask = try #require(TestImages.make(width: 32, height: 32))
    var job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: .default)
    job.maskSettings = MaskSettings(blur: 9, outset: 9, preserveOriginal: false)
    let request = try JobMapper.request(for: job, inputs: GenerationInputs(mask: mask, enableInpainting: true))
    #expect(request.mask == nil)
    #expect(request.configuration.maskBlur != 9)
    #expect(!request.configuration.enableInpainting)
  }

  @Test func theMaskSettingsAreClampedBeforeTheyAreSent() throws {
    let image = try #require(TestImages.make(width: 32, height: 32))
    let mask = try #require(TestImages.make(width: 32, height: 32))
    var job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: .default)
    job.maskSettings = MaskSettings(blur: 900, outset: 900, preserveOriginal: true)
    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
    #expect(request.configuration.maskBlur == Float(MaskSettings.blurRange.upperBound))
    #expect(request.configuration.maskBlurOutset == Int32(MaskSettings.outsetRange.upperBound))
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

import CoreGraphics

enum TestImages {
  static func make(width: Int, height: Int) -> CGImage? {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context?.makeImage()
  }
}
