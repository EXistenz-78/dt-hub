import FlatBuffers
import Foundation
import Testing
@testable import DrawThingsClient

@Suite("Configuration")
struct ConfigurationTests {
    /// A real "Copy Configuration" export from the Draw Things app (Z Image with a LoRA).
    static let appExport = #"""
{
  "aestheticScore": 6,
  "batchCount": 10,
  "batchSize": 1,
  "causalInference": 0,
  "causalInferencePad": 0,
  "cfgZeroInitSteps": 0,
  "cfgZeroStar": false,
  "clipLText": null,
  "clipSkip": 1,
  "clipWeight": 1,
  "colorCalibration": "disabled",
  "compressionArtifacts": "disabled",
  "compressionArtifactsQuality": 43.1,
  "controls": [],
  "cropLeft": 0,
  "cropTop": 0,
  "decodingTileHeight": 640,
  "decodingTileOverlap": 128,
  "decodingTileWidth": 640,
  "diffusionTileHeight": 1024,
  "diffusionTileOverlap": 128,
  "diffusionTileWidth": 1024,
  "expandPromptToJson": false,
  "faceRestoration": null,
  "fps": 5,
  "guidanceEmbed": 3.5,
  "guidanceScale": 1,
  "guidingFrameNoise": 0.02,
  "height": 1280,
  "hiresFix": false,
  "hiresFixHeight": 1024,
  "hiresFixStrength": 0.7,
  "hiresFixWidth": 1024,
  "id": 0,
  "imageGuidanceScale": 1.5,
  "imagePriorSteps": 5,
  "loras": [
    {
      "file": "zit_natalie_illustrated_lora_f16.ckpt",
      "mode": "all",
      "weight": 0.65
    }
  ],
  "maskBlur": 1.5,
  "maskBlurOutset": 0,
  "model": "z_image_turbo_1.0_q8p.ckpt",
  "motionScale": 127,
  "negativeAestheticScore": 2.5,
  "negativeOriginalImageHeight": 640,
  "negativeOriginalImageWidth": 640,
  "negativePromptForImagePrior": true,
  "numFrames": 14,
  "openClipGText": null,
  "originalImageHeight": 1280,
  "originalImageWidth": 1280,
  "preserveOriginalAfterInpaint": true,
  "refinerModel": null,
  "refinerStart": 0.85,
  "resolutionDependentShift": false,
  "sampler": 17,
  "seed": 945446116,
  "seedMode": 2,
  "separateClipL": false,
  "separateOpenClipG": false,
  "separateT5": false,
  "sharpness": 0,
  "shift": 3,
  "speedUpWithGuidanceEmbed": true,
  "stage2Guidance": 1,
  "stage2Shift": 1,
  "stage2Steps": 10,
  "startFrameGuidance": 1,
  "steps": 8,
  "stochasticSamplingGamma": 0.3,
  "strength": 1,
  "t5Text": null,
  "t5TextEncoder": true,
  "targetImageHeight": 1280,
  "targetImageWidth": 1280,
  "teaCache": false,
  "teaCacheEnd": -1,
  "teaCacheMaxSkipSteps": 3,
  "teaCacheStart": 5,
  "teaCacheThreshold": 0.2,
  "tiledDecoding": false,
  "tiledDiffusion": false,
  "upscaler": null,
  "upscalerScaleFactor": 0,
  "width": 1280,
  "zeroNegativePrompt": false
}
"""#

    private func root(_ configuration: DrawThingsConfiguration) throws -> GenerationConfiguration {
        var buffer = ByteBuffer(data: try configuration.toFlatBufferData())
        return try getCheckedRoot(byteBuffer: &buffer)
    }

    // MARK: JSON

    @Test func parsesAppExport() throws {
        let configuration = try DrawThingsConfiguration.fromJSON(Self.appExport)
        #expect(configuration.width == 1280)
        #expect(configuration.seed == 945_446_116)
        #expect(configuration.seedMode == .scalealike)
        #expect(configuration.sampler.rawValue == 17)
        #expect(configuration.loras == [LoRAConfig(file: "zit_natalie_illustrated_lora_f16.ckpt", weight: 0.65, mode: .all)])
        #expect(configuration.colorCalibration == .disabled)
        #expect(!configuration.causalInferenceEnabled)
        #expect(throws: Never.self) { try configuration.validate() }
    }

    @Test func roundTripsThroughJSON() throws {
        var configuration = DrawThingsConfiguration(width: 768, height: 1024, steps: 12, model: "flux_2_klein_4b_q8p.ckpt", seed: 42)
        configuration.loras = [LoRAConfig(file: "style.ckpt", weight: 0.7, mode: .refiner)]
        configuration.controls = [ControlConfig(file: "depth.ckpt", weight: 0.8, guidanceEnd: 0.6, controlMode: .control,
                                                noPrompt: true, inputOverride: .depth, targetBlocks: ["a", "b"])]
        configuration.compressionArtifacts = .h265
        configuration.colorCalibration = .lab
        configuration.causalInferenceEnabled = true
        configuration.causalInference = 5
        configuration.usesSolAttention = true
        configuration.shiftForAudio = 2.5
        configuration.refinerModel = "refiner.ckpt"
        configuration.name = "Test"
        configuration.enableInpainting = true

        let decoded = try DrawThingsConfiguration.fromJSON(try configuration.toJSON())
        #expect(decoded == configuration)
    }

    @Test func writesTheAppsSpellings() throws {
        var configuration = DrawThingsConfiguration(model: "m.ckpt")
        configuration.loras = [LoRAConfig(file: "l.ckpt", mode: .base)]
        configuration.controls = [ControlConfig(file: "c.ckpt", controlMode: .prompt, inputOverride: .inpaint)]
        let object = try #require(JSONSerialization.jsonObject(with: Data(try configuration.toJSON(includeSeed: false).utf8)) as? [String: Any])
        #expect(object["seed"] as? Int == -1)
        #expect(object["id"] as? Int == 0)
        #expect(object["colorCalibration"] as? String == "none")
        #expect(object["compressionArtifacts"] as? String == "disabled")
        #expect((object["loras"] as? [[String: Any]])?.first?["mode"] as? String == "base")
        let control = try #require((object["controls"] as? [[String: Any]])?.first)
        #expect(control["controlImportance"] as? String == "prompt")
        #expect(control["inputOverride"] as? String == "inpaint")
        #expect(object["refinerModel"] is NSNull)
        #expect(object["enableInpainting"] == nil)
    }

    @Test func acceptsDrawThingsKitSpellings() throws {
        let json = #"{"loras":[{"file":"a.ckpt","weight":1,"mode":2}],"controls":[{"file":"c.ckpt","controlMode":1}],"colorCalibration":"none","seed":-1}"#
        let configuration = try DrawThingsConfiguration.fromJSON(json)
        #expect(configuration.loras.first?.mode == .refiner)
        #expect(configuration.controls.first?.controlMode == .prompt)
        #expect(configuration.colorCalibration == .disabled)
        #expect(configuration.seed == nil)
    }

    @Test func missingKeysUseDefaults() throws {
        let configuration = try DrawThingsConfiguration.fromJSON(#"{"model":"x.ckpt","steps":7}"#)
        var expected = DrawThingsConfiguration(model: "x.ckpt")
        expected.steps = 7
        #expect(configuration == expected)
    }

    @Test func unknownSamplerIsRejected() {
        #expect(throws: DecodingError.self) { try DrawThingsConfiguration.fromJSON(#"{"sampler":120}"#) }
    }

    @Test func mergeOnlyChangesPresentKeys() throws {
        var configuration = DrawThingsConfiguration(width: 1024, height: 1024, steps: 30, model: "base.ckpt", seed: 7)
        configuration.loras = [LoRAConfig(file: "keep.ckpt")]
        try configuration.mergeJSON(#"{"steps": 8, "guidanceScale": 1.5, "seed": null}"#)
        #expect(configuration.steps == 8)
        #expect(configuration.guidanceScale == 1.5)
        #expect(configuration.width == 1024)
        #expect(configuration.model == "base.ckpt")
        #expect(configuration.loras.map(\.file) == ["keep.ckpt"])
        try configuration.mergeJSON("{}")
        #expect(configuration.steps == 8)
    }

    @Test func validateJSONDescribesProblems() {
        #expect(DrawThingsConfiguration.validateJSON("").isValid)
        #expect(DrawThingsConfiguration.validateJSON(Self.appExport).isValid)
        #expect(DrawThingsConfiguration.validateJSON("{nope").error == "Invalid JSON syntax")
        #expect(DrawThingsConfiguration.validateJSON(#"{"steps":"many"}"#).error?.contains("steps") == true)
        #expect(DrawThingsConfiguration.validateJSON(#"{"width":16}"#).error?.contains("width") == true)
    }

    // MARK: Validation

    /// Applies an invalid value for `field`.
    private static func invalidate(_ field: String, _ c: inout DrawThingsConfiguration) {
        switch field {
        case "width": c.width = 32
        case "height": c.height = -64
        case "steps": c.steps = 0
        case "batchSize": c.batchSize = 5
        case "upscalerScaleFactor": c.upscalerScaleFactor = 300
        case "strength": c.strength = 1.5
        case "clipSkip": c.clipSkip = -1
        case "guidanceScale": c.guidanceScale = .nan
        case "hiresFixWidth": c.hiresFix = true
        case "model": c.model = ""
        default: Issue.record("unknown field \(field)")
        }
    }

    @Test(arguments: ["width", "height", "steps", "batchSize", "upscalerScaleFactor", "strength",
                      "clipSkip", "guidanceScale", "hiresFixWidth", "model"])
    func invalidValuesThrowInsteadOfTrapping(field: String) {
        var configuration = DrawThingsConfiguration()
        Self.invalidate(field, &configuration)
        #expect {
            try configuration.toFlatBufferData()
        } throws: { error in
            guard case DrawThingsError.invalidConfiguration(let reported, _) = error else { return false }
            return reported == field
        }
    }

    // MARK: FlatBuffer

    @Test func sizesAreSentInUnitsOf64RoundedDown() throws {
        let encoded = try root(DrawThingsConfiguration(width: 1000, height: 700, model: "m.ckpt"))
        #expect(encoded.startWidth == 15)
        #expect(encoded.startHeight == 10)
    }

    @Test func newUpstreamFieldsAreEncoded() throws {
        var configuration = DrawThingsConfiguration(model: "ltx_2.3_22b_distilled_f16.ckpt")
        configuration.shiftForAudio = 1.25
        configuration.usesSolAttention = true
        configuration.solAttentionStart = 4
        configuration.solAttentionTau = 0.75
        let encoded = try root(configuration)
        #expect(encoded.shiftForAudio == 1.25)
        #expect(encoded.usesSolAttention)
        #expect(encoded.solAttentionStart == 4)
        #expect(encoded.solAttentionTau == 0.75)
    }

    @Test func controlFieldsAreEncoded() throws {
        var configuration = DrawThingsConfiguration(model: "m.ckpt")
        configuration.controls = [ControlConfig(file: "c.ckpt", noPrompt: true, downSamplingRate: 2, inputOverride: .pose, targetBlocks: ["x"])]
        let control = try #require(try root(configuration).controls(at: 0))
        #expect(control.noPrompt)
        #expect(control.downSamplingRate == 2)
        #expect(control.inputOverride == .pose)
        #expect(control.targetBlocksCount == 1)
    }

    @Test func nilSeedIsRandomAndExplicitSeedIsKept() throws {
        #expect(try root(DrawThingsConfiguration(model: "m.ckpt", seed: 123)).seed == 123)
        let a = try root(DrawThingsConfiguration(model: "m.ckpt")).seed
        let b = try root(DrawThingsConfiguration(model: "m.ckpt")).seed
        let c = try root(DrawThingsConfiguration(model: "m.ckpt")).seed
        #expect(!(a == b && b == c))
    }
}
