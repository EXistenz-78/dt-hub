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
