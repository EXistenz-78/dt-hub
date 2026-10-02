import Foundation
import Testing

@testable import HubKit

struct MaskContractTests {
  @Test func maskSettingsStartAtDrawThingsDefaults() {
    let settings = MaskSettings()
    #expect(settings.blur == 1.5 && settings.outset == 0 && settings.preserveOriginal)
  }

  @Test func savedInputsWithoutAMaskStillLoad() throws {
    let old = Data(#"{"framing":{"mode":"fill","offsetX":0,"offsetY":0}}"#.utf8)
    let inputs = try JSONDecoder().decode(ControlInputs.self, from: old)
    #expect(inputs.mask == nil)
    #expect(inputs.maskSettings == MaskSettings())
  }

  @Test func aMaskWithoutAnImageIsNotKept() throws {
    let json = Data(#"{"mask":{"fileName":"x.png","coverage":0.2}}"#.utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: json).mask == nil)
  }

  @Test func aDrawingWithoutAnImageIsNotKept() throws {
    let json = Data(#"{"paint":{"fileName":"x.png"}}"#.utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: json).paint == nil)
    let withImage = Data(
      #"{"image":{"id":"7CB25000-FFE8-4BF4-B1F5-EB90BFCD8837","name":"a.png","pixelWidth":8,"pixelHeight":8,"source":{"result":{}},"fileName":"a.png"},"paint":{"fileName":"x.png"}}"#
        .utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: withImage).paint == PaintReference(fileName: "x.png"))
  }

  @Test func damagedMaskSettingsFallBackToTheDefaults() throws {
    let json = Data(#"{"maskSettings":{"blur":"lots","outset":999}}"#.utf8)
    let settings = try JSONDecoder().decode(ControlInputs.self, from: json).maskSettings
    #expect(settings.blur == 1.5)
    #expect(settings.outset == MaskSettings.outsetRange.upperBound)
  }

  @Test func aJobCarriesTheMaskSettingsAndOldJobsLoad() throws {
    var job = GenerationJob(prompt: "x", model: "m", parameters: GenerationParameters())
    #expect(job.maskSettings == nil)
    job.maskSettings = MaskSettings(blur: 3, outset: 4, preserveOriginal: false)
    let back = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
    #expect(back.maskSettings == job.maskSettings)
    let old = Data(#"{"prompt":"x","model":"m","parameters":{}}"#.utf8)
    #expect(try JSONDecoder().decode(GenerationJob.self, from: old).maskSettings == nil)
  }

  @Test func onlyAnInpaintingModelNeedsTheInpaintControl() {
    func capabilities(_ modifier: String?) -> ModelCapabilities {
      ModelCapabilities(
        guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
        clipSkip: false, nativeSize: nil, modifier: modifier)
    }
    #expect(capabilities("inpainting").needsInpaintControl)
    #expect(!capabilities("kontext").needsInpaintControl)
    #expect(!capabilities(nil).needsInpaintControl)
  }
}
