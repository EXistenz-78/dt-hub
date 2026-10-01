import DrawThingsClient
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct ConfigurationCodecTests {
  let codec = DrawThingsConfigurationCodec()
  let state = ConfigurationState(model: "flux_2_klein_9b_f16.ckpt", parameters: GenerationParameters(seed: 42, randomSeed: false))

  func object(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
  }

  @Test func exportsTheCompleteConfiguration() {
    let json = object(codec.exportJSON(state))
    #expect(json["model"] as? String == "flux_2_klein_9b_f16.ckpt")
    #expect(json["steps"] as? Int == 8)
    #expect(json["seed"] as? Int == 42)
    #expect(json.count > 60)
  }

  @Test func aRandomSeedIsExportedAsMinusOne() {
    var random = state
    random.parameters.randomSeed = true
    #expect(object(codec.exportJSON(random))["seed"] as? Int == -1)
  }

  @Test func aPartialTextChangesOnlyItsKeys() throws {
    let result = try codec.apply(json: #"{"steps": 30, "guidanceScale": 4.5, "sampler": 2}"#, to: state)
    var expected = state.parameters
    expected.steps = 30
    expected.guidanceScale = 4.5
    expected.sampler = .ddim
    #expect(result.parameters == expected)
    #expect(result.model == state.model)
  }

  @Test func theModelComesFromTheText() throws {
    let result = try codec.apply(json: #"{"model": "z_image_turbo_1.0_f16.ckpt"}"#, to: state)
    #expect(result.model == "z_image_turbo_1.0_f16.ckpt")
  }

  @Test func aNegativeSeedMeansRandomAndANumberMeansFixed() throws {
    let random = try codec.apply(json: #"{"seed": -1}"#, to: state)
    #expect(random.parameters.randomSeed)
    let fixed = try codec.apply(json: #"{"seed": 7}"#, to: ConfigurationState(model: "m", parameters: GenerationParameters()))
    #expect(!fixed.parameters.randomSeed)
    #expect(fixed.parameters.seed == 7)
  }

  @Test func advancedValuesAreReadBack() throws {
    let json = #"{"hiresFix": true, "hiresFixWidth": 512, "hiresFixHeight": 512, "teaCache": true, "colorCalibration": "lab", "compressionArtifacts": "jpeg", "refinerModel": "r.ckpt", "clipSkip": 2}"#
    let advanced = try codec.apply(json: json, to: state).parameters.advanced
    #expect(advanced.hiresFix && advanced.hiresFixWidth == 512 && advanced.hiresFixHeight == 512)
    #expect(advanced.teaCache)
    #expect(advanced.colorCalibration)
    #expect(advanced.compressionArtifacts == .jpeg)
    #expect(advanced.refinerModel == "r.ckpt")
    #expect(advanced.clipSkip == 2)
  }

  @Test func loRAsKeepTheirTriggerWords() throws {
    var withTrigger = state
    withTrigger.parameters.loras = [LoRASelection(file: "a_lora_f16.ckpt", weight: 1, trigger: "vintage tarot style")]
    let json = #"{"loras": [{"file": "a_lora_f16.ckpt", "weight": 0.6, "mode": "base"}, {"file": "b_lora_f16.ckpt", "weight": 1}]}"#
    let loras = try codec.apply(json: json, to: withTrigger).parameters.loras
    #expect(loras.map(\.file) == ["a_lora_f16.ckpt", "b_lora_f16.ckpt"])
    #expect(loras[0].weight == 0.6 && loras[0].mode == .base && loras[0].trigger == "vintage tarot style")
    #expect(loras[1].trigger == "")
  }

  @Test func settingsWithoutACardAreKeptAsExtra() throws {
    let result = try codec.apply(json: #"{"fps": 24, "solAttentionTau": 0.7, "steps": 20}"#, to: state)
    #expect(result.parameters.extra == ["fps": .int(24), "solAttentionTau": .double(0.7)])
    #expect(result.parameters.steps == 20)
    // They go out with the next request and come back in the export.
    let request = JobMapper.request(for: GenerationJob(prompt: "p", model: "m", parameters: result.parameters)).configuration
    #expect(request.fps == 24)
    #expect(abs(request.solAttentionTau - 0.7) < 0.0001)
    #expect(object(codec.exportJSON(result))["fps"] as? Int == 24)
  }

  @Test func aSettingSetBackToItsDefaultIsNoLongerExtra() throws {
    let set = try codec.apply(json: #"{"fps": 24}"#, to: state)
    let reset = try codec.apply(json: #"{"fps": 5}"#, to: set)
    #expect(reset.parameters.extra.isEmpty)
  }

  @Test func aCompleteExportAddsNoExtraSettings() throws {
    let full = codec.exportJSON(state)
    #expect(try codec.apply(json: full, to: state).parameters.extra.isEmpty)
  }

  @Test func extraSettingsAddUpAcrossApplies() throws {
    let first = try codec.apply(json: #"{"fps": 24}"#, to: state)
    let second = try codec.apply(json: #"{"motionScale": 100}"#, to: first)
    #expect(second.parameters.extra == ["fps": .int(24), "motionScale": .int(100)])
  }

  @Test func anEmptyTextOrAnEmptyObjectChangesNothing() throws {
    #expect(try codec.apply(json: "", to: state) == state)
    #expect(try codec.apply(json: "{}", to: state) == state)
  }

  @Test func aBadTextIsRejectedWithAReason() {
    #expect(codec.validate("not json") != nil)
    #expect(codec.validate("[1, 2]") != nil)
    #expect(codec.validate(#"{"steps": "many"}"#) != nil)
    #expect(codec.validate(#"{"width": 10}"#) != nil)
    #expect(codec.validate(#"{"steps": 8}"#) == nil)
    #expect(codec.validate("  ") == nil)
    #expect(throws: ConfigurationError.self) { try codec.apply(json: "not json", to: state) }
  }

  @Test func unknownKeysAreListedAndIgnored() throws {
    #expect(codec.unknownKeys(in: #"{"steps": 8, "stepz": 3, "futureThing": true}"#) == ["futureThing", "stepz"])
    let result = try codec.apply(json: #"{"stepz": 3}"#, to: state)
    #expect(result == state)
  }

  @Test func exportThenApplyReproducesTheParameters() throws {
    var rich = state
    rich.parameters.width = 832
    rich.parameters.height = 1216
    rich.parameters.guidanceScale = 4.5
    rich.parameters.shift = 2.5
    rich.parameters.cfgZeroStar = true
    rich.parameters.cfgZeroInitSteps = 2
    rich.parameters.sampler = .dpmppSDEKarras
    rich.parameters.batchSize = 2
    rich.parameters.loras = [LoRASelection(file: "a_lora_f16.ckpt", weight: 0.65, mode: .refiner, trigger: "t")]
    rich.parameters.advanced.refinerModel = "r.ckpt"
    rich.parameters.advanced.refinerStart = 0.6
    rich.parameters.advanced.hiresFix = true
    rich.parameters.advanced.hiresFixWidth = 576
    rich.parameters.advanced.hiresFixHeight = 832
    rich.parameters.advanced.guidanceEmbed = 4.5
    rich.parameters.advanced.separateT5 = true
    rich.parameters.advanced.t5Text = "long text"
    rich.parameters.advanced.aestheticScore = 7.5
    rich.parameters.advanced.teaCache = true
    rich.parameters.advanced.teaCacheThreshold = 0.1
    rich.parameters.advanced.compressionArtifacts = .h265
    rich.parameters.advanced.compressionQuality = 50
    rich.parameters.extra = ["fps": .int(12)]
    let json = codec.exportJSON(rich)
    let back = try codec.apply(json: json, to: ConfigurationState(model: "other.ckpt", parameters: GenerationParameters(extra: rich.parameters.extra)))
    #expect(back.model == rich.model)
    // The JSON carries no trigger word: a LoRA new to the tab comes back without one.
    var expected = rich.parameters.clamped()
    expected.loras[0].trigger = ""
    #expect(back.parameters == expected)
    #expect(codec.exportJSON(back) == json)
  }

  @Test func theModeledKeysAreRealKeys() {
    let known = DrawThingsConfigurationCodec.knownKeys
    #expect(DrawThingsConfigurationCodec.modeledKeys.isSubset(of: known))
    #expect(DrawThingsConfigurationCodec.extraKeys.contains("fps"))
    #expect(!DrawThingsConfigurationCodec.extraKeys.contains("steps"))
    #expect(!DrawThingsConfigurationCodec.extraKeys.contains("name"))
  }
}
