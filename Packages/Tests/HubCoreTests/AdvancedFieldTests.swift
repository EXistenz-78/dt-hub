import HubKit
import Testing

@testable import HubCore

struct AdvancedFieldTests {
  let flux1 = CatalogModel(
    file: "flux_1_dev_q5p.ckpt", name: "FLUX.1 [dev]", family: "flux1",
    capabilities: ModelCapabilities(
      guidanceEmbed: true, teaCache: true, clipL: true, openClipG: false, t5: true,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
  let klein = CatalogModel(
    file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2 [klein] 9B", family: "flux2_9b",
    capabilities: ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
  let sd15 = CatalogModel(
    file: "juggernaut_reborn_q6p_q8p.ckpt", name: "Juggernaut Reborn", family: "v1",
    capabilities: ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: true, openClipG: false, t5: false,
      optionalT5: false, clipSkip: true, nativeSize: 512))
  let sdxl = CatalogModel(
    file: "sdxl.ckpt", name: "SDXL", family: "sdxl_base_v0.9",
    capabilities: ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: true, openClipG: true, t5: false,
      optionalT5: false, clipSkip: true, nativeSize: 1024))

  func shown(_ model: CatalogModel?, sampler: Sampler = .uniPCTrailing) -> Set<AdvancedField> {
    Set(AdvancedField.allCases.filter { $0.isShown(for: model, sampler: sampler) })
  }

  @Test func fieldsFollowWhatTheModelSupports() {
    #expect(shown(flux1).isSuperset(of: [.guidanceEmbed, .teaCache, .separateClipL, .separateT5]))
    #expect(shown(flux1).isDisjoint(with: [.clipSkip, .separateOpenClipG, .sdxlConditioning, .zeroNegativePrompt]))
    #expect(shown(klein).isDisjoint(with: [.guidanceEmbed, .teaCache, .clipSkip, .separateClipL, .separateT5]))
    #expect(shown(sd15).contains(.clipSkip))
    // One encoder only: no separate text.
    #expect(!shown(sd15).contains(.separateClipL))
    #expect(shown(sdxl).isSuperset(of: [.clipSkip, .separateClipL, .separateOpenClipG, .sdxlConditioning, .zeroNegativePrompt]))
  }

  @Test func refinerHiresUpscalerAndOutputApplyToEveryModel() {
    for model in [flux1, klein, sd15, sdxl] {
      #expect(shown(model).isSuperset(of: [.refiner, .hiresFix, .upscaler, .faceRestoration, .sharpness, .tiledDecoding, .tiledDiffusion, .colorCalibration, .compressionArtifacts]))
    }
  }

  @Test func theSamplingGammaAppliesToTCDSamplersOnly() {
    #expect(shown(klein, sampler: .tcd).contains(.stochasticSamplingGamma))
    #expect(shown(klein, sampler: .tcdTrailing).contains(.stochasticSamplingGamma))
    #expect(!shown(klein).contains(.stochasticSamplingGamma))
  }

  @Test func anUnknownModelShowsEverything() {
    #expect(shown(nil, sampler: .tcd) == Set(AdvancedField.allCases))
  }

  @Test func everyFieldBelongsToACard() {
    #expect(AdvancedCard.allCases.allSatisfy { !$0.fields.isEmpty })
    #expect(AdvancedCard.allCases.flatMap(\.fields).count == AdvancedField.allCases.count)
  }

  @Test func reportsAndResetsModifiedFields() {
    var advanced = AdvancedParameters()
    #expect(advanced.modifiedFields.isEmpty)
    advanced.teaCacheThreshold = 0.1
    advanced.clipSkip = 2
    #expect(advanced.modifiedFields == [.clipSkip, .teaCache])
    advanced.reset(.teaCache)
    #expect(advanced.modifiedFields == [.clipSkip])
  }

  @Test func hiddenModifiedFieldsAreThoseTheModelDoesNotUse() {
    var advanced = AdvancedParameters()
    advanced.clipSkip = 2
    advanced.sharpness = 5
    #expect(advanced.hiddenModifiedFields(for: klein, sampler: .uniPCTrailing) == [.clipSkip])
    #expect(advanced.hiddenModifiedFields(for: sd15, sampler: .uniPCTrailing).isEmpty)
  }
}

struct AdvancedCompositionTests {
  let klein = AdvancedFieldTests().klein
  let sd15 = AdvancedFieldTests().sd15

  func compose(_ parameters: GenerationParameters, model: CatalogModel, catalog extra: ModelCatalog? = nil) -> AdvancedParameters {
    let catalog = extra ?? ModelCatalog(
      models: [klein, sd15], loras: [], fileCount: 4,
      upscalers: ["realesrgan_x4plus_f16.ckpt"], faceRestorers: ["restoreformer_v1.0_f16.ckpt"])
    return JobComposer.batches(
      prompt: "p", negativePrompt: "", model: model.file, family: model.family,
      parameters: parameters, catalog: catalog) { 1 }[0].parameters.advanced
  }

  @Test func fieldsTheModelDoesNotUseAreNotSent() {
    var parameters = GenerationParameters()
    parameters.advanced.clipSkip = 2
    parameters.advanced.sharpness = 4
    #expect(compose(parameters, model: klein).clipSkip == 1)
    #expect(compose(parameters, model: klein).sharpness == 4)
    #expect(compose(parameters, model: sd15).clipSkip == 2)
  }

  @Test func filesTheServerDoesNotListAreNotSent() {
    var parameters = GenerationParameters()
    parameters.advanced.refinerModel = "gone.ckpt"
    parameters.advanced.upscaler = "gone_x4.ckpt"
    parameters.advanced.faceRestoration = "restoreformer_v1.0_f16.ckpt"
    let sent = compose(parameters, model: klein)
    #expect(sent.refinerModel == "")
    #expect(sent.upscaler == "")
    #expect(sent.faceRestoration == "restoreformer_v1.0_f16.ckpt")
  }

  @Test func anAutomaticHiresFixStartsAtTheNativeSize() {
    var parameters = GenerationParameters(width: 1536, height: 1024)
    parameters.advanced.hiresFix = true
    let sent = compose(parameters, model: sd15)
    #expect(sent.hiresFix)
    #expect(sent.hiresFixWidth == 512)
    #expect(sent.hiresFixHeight == 512)
  }

  @Test func aHiresFixNotSmallerThanTheImageIsDropped() {
    var parameters = GenerationParameters(width: 512, height: 512)
    parameters.advanced.hiresFix = true
    #expect(!compose(parameters, model: sd15).hiresFix)
  }
}
