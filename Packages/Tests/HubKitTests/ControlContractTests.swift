import Foundation
import Testing

@testable import HubKit

struct ControlContractTests {
  func image(source: ReferenceImage.Source = .pasteboard) -> ReferenceImage {
    ReferenceImage(id: UUID(), name: "cat.png", pixelWidth: 800, pixelHeight: 600, source: source, fileName: "a.png")
  }

  @Test func referenceImagesSurviveEncoding() throws {
    for source in [ReferenceImage.Source.file(path: "/x/cat.png"), .result, .pasteboard, .plugin(id: "pm2")] {
      let original = image(source: source)
      let decoded = try JSONDecoder().decode(ReferenceImage.self, from: JSONEncoder().encode(original))
      #expect(decoded == original)
    }
  }

  @Test func emptyControlInputsLoadFromAnyOlderFile() throws {
    let decoded = try JSONDecoder().decode(ControlInputs.self, from: Data("{}".utf8))
    #expect(decoded == ControlInputs())
    #expect(decoded.image == nil)
    #expect(decoded.framing == Framing())
    #expect(decoded.strength == nil)
  }

  @Test func strengthIsAutomaticUntilTheUserChoosesOne() {
    var inputs = ControlInputs()
    #expect(inputs.effectiveStrength(editModel: true) == 1.0)
    #expect(inputs.effectiveStrength(editModel: false) == 0.7)
    inputs.strength = 0.4
    #expect(inputs.effectiveStrength(editModel: true) == 0.4)
    inputs.strength = 3
    #expect(inputs.effectiveStrength(editModel: false) == 1.0)
    inputs.strength = -1
    #expect(inputs.effectiveStrength(editModel: false) == 0.0)
  }

  @Test func theFramingStartsCentered() {
    let framing = Framing()
    #expect(framing.mode == .fill)
    #expect(framing.offsetX == 0)
    #expect(framing.offsetY == 0)
    #expect(Framing(offsetX: 5, offsetY: -5).clamped() == Framing(offsetX: 1, offsetY: -1))
  }

  @Test func noInputsMeansTextToImage() {
    #expect(GenerationInputs.none.isEmpty)
  }

  @Test func oldJobsHaveNoImageStrength() throws {
    let job = GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default)
    #expect(job.imageStrength == nil)
    let old = try JSONDecoder().decode(
      GenerationJob.self, from: Data(#"{"prompt":"p","model":"m.ckpt","parameters":{}}"#.utf8))
    #expect(old.imageStrength == nil)
    var withImage = job
    withImage.imageStrength = 0.6
    let round = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(withImage))
    #expect(round.imageStrength == 0.6)
  }

  @Test func editModelsAreRecognisedByTheirModifier() {
    func caps(_ modifier: String?) -> ModelCapabilities {
      var c = ModelCapabilities.unknown
      c.modifier = modifier
      return c
    }
    for edit in ["kontext", "kontext_kv", "qwenimage_edit_plus", "editing"] {
      #expect(caps(edit).isEditModel)
    }
    for other in [nil, "inpainting", "none", "depth"] as [String?] {
      #expect(!caps(other).isEditModel)
    }
  }

  @Test func moodboardEntriesSurviveEncodingAndOlderFilesHaveNone() throws {
    let entry = MoodboardEntry(image: image(), isOn: false)
    #expect(entry.id == entry.image.id)
    var inputs = ControlInputs()
    inputs.moodboard = [entry]
    let decoded = try JSONDecoder().decode(ControlInputs.self, from: JSONEncoder().encode(inputs))
    #expect(decoded == inputs)
    let old = try JSONDecoder().decode(ControlInputs.self, from: Data(#"{"strength": 0.5}"#.utf8))
    #expect(old.moodboard.isEmpty)
    // A damaged entry does not take the others with it.
    let mixed = try JSONDecoder().decode(
      ControlInputs.self, from: Data(#"{"moodboard": [{"nope": 1}]}"#.utf8))
    #expect(mixed.moodboard.isEmpty)
  }

  @Test func theHintsMakeTheInputsNonEmpty() {
    var inputs = GenerationInputs.none
    #expect(inputs.isEmpty)
    inputs.hints = [GenerationHint(imageData: Data([1, 2, 3]), weight: 0.5)]
    #expect(!inputs.isEmpty)
  }

  @Test func jobsRecordHowManyMoodboardPicturesWentAndOldOnesHaveNone() throws {
    var job = GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default)
    #expect(job.moodboardCount == 0)
    job.moodboardCount = 3
    let round = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
    #expect(round.moodboardCount == 3)
    let old = try JSONDecoder().decode(
      GenerationJob.self, from: Data(#"{"prompt":"p","model":"m.ckpt","parameters":{}}"#.utf8))
    #expect(old.moodboardCount == 0)
  }
}
