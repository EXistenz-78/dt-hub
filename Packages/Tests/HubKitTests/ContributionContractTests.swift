import Foundation
import Testing

@testable import HubKit

struct ContributionContractTests {
  private func overlay(_ json: String) -> FieldOverlay {
    let value = try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    guard case .object(let object) = value else { fatalError("not an object") }
    return FieldOverlay(json: object)
  }

  @Test func fieldsAreReadByKeyAndKind() {
    let read = overlay(
      #"{"prompt":"a cat","negativePrompt":"blur","steps":4,"guidanceScale":1,"shift":3,"sampler":16,"cfgZeroStar":true,"seed":7,"randomSeed":false,"width":1024.0}"#
    )
    #expect(read.values[.prompt] == .text("a cat"))
    #expect(read.values[.steps] == .int(4))
    #expect(read.values[.guidanceScale] == .double(1))
    #expect(read.values[.sampler] == .int(16))
    #expect(read.values[.cfgZeroStar] == .bool(true))
    #expect(read.values[.randomSeed] == .bool(false))
    #expect(read.values[.width] == .int(1024))
  }

  @Test func theSamplerCanBeNamedByItsDisplayName() {
    #expect(overlay(#"{"sampler":"ddim trailing"}"#).values[.sampler] == .int(Sampler.ddimTrailing.rawValue))
    #expect(overlay(#"{"sampler":"not a sampler"}"#).isEmpty)
    #expect(overlay(#"{"sampler":99}"#).isEmpty)
  }

  @Test func unknownKeysAndValuesOfTheWrongKindAreLeftOut() {
    let read = overlay(#"{"model":"flux.ckpt","steps":"four","prompt":3,"cfgZeroStar":1,"width":1000.5,"shift":null}"#)
    #expect(read.isEmpty)
  }

  @Test func appliedValuesAreLimitedLikeTheCards() {
    let fields = overlay(#"{"width":1000,"steps":999,"guidanceScale":-4,"batchSize":9,"prompt":"x"}"#)
      .applied(to: GenerationFields())
    #expect(fields.parameters.width == 1024)
    #expect(fields.parameters.steps == GenerationParameters.stepsRange.upperBound)
    #expect(fields.parameters.guidanceScale == 0)
    #expect(fields.parameters.batchSize == GenerationParameters.batchSizeRange.upperBound)
    #expect(fields.prompt == "x")
  }

  @Test func valueOfAndSetAgreeForEveryField() {
    var fields = GenerationFields()
    for field in ContributionField.allCases {
      let value = fields.value(of: field)
      fields.set(value, for: field)
      #expect(fields.value(of: field) == value)
    }
  }

  @Test func aContributionIsReadWithItsParts() throws {
    let message = Data(
      """
      {"type":"contribute","fields":{"steps":4},"loras":[{"file":"sun.ckpt","weight":0.6,"mode":"all"},{"weight":1}],
       "moodboard":[{"path":"/tmp/a.png","name":"Sphere"},{"path":"/tmp/b.png"},{"name":"no path"}],
       "startImage":{"path":"/tmp/s.png"},
       "pipeline":{"name":"Match","steps":[
         {"title":"Overcast","fields":{"steps":4},"loras":[]},
         {"fields":{"guidanceScale":1},"moodboard":[{"path":"/tmp/a.png"}],"useOutputAsStart":true},
         "junk"]}}
      """.utf8)
    let contribution = try #require(PluginContribution(message: message))
    #expect(contribution.fields.values[.steps] == .int(4))
    #expect(contribution.loras.map(\.file) == ["sun.ckpt"])
    #expect(contribution.loras.first?.weight == 0.6)
    #expect(contribution.moodboard == [PluginImageRef(name: "Sphere", path: "/tmp/a.png"), PluginImageRef(name: "b.png", path: "/tmp/b.png")])
    #expect(contribution.startImage == PluginImageRef(name: "s.png", path: "/tmp/s.png"))
    let pipeline = try #require(contribution.pipeline)
    #expect(pipeline.name == "Match")
    #expect(pipeline.steps.count == 2)
    #expect(pipeline.steps[0].title == "Overcast")
    #expect(pipeline.steps[0].loras == [])
    #expect(pipeline.steps[0].useOutputAsStart == false)
    #expect(pipeline.steps[1].loras == nil)
    #expect(pipeline.steps[1].moodboard?.count == 1)
    #expect(pipeline.steps[1].useOutputAsStart)
  }

  @Test func aMessageThatIsNotAnObjectOrCarriesNothingIsRecognised() {
    #expect(PluginContribution(message: Data("[1]".utf8)) == nil)
    #expect(PluginContribution(message: Data("nope".utf8)) == nil)
    #expect(PluginContribution(message: Data(#"{"type":"contribute"}"#.utf8))?.isEmpty == true)
    #expect(PluginContribution(message: Data(#"{"pipeline":{"steps":[]}}"#.utf8))?.pipeline == nil)
  }

  @Test func theFailureAnswerNamesTheProblem() {
    let data = PluginMessageType.failure("no way")
    #expect(PluginMessageType.of(data) == PluginMessageType.error)
    #expect(String(decoding: data, as: UTF8.self).contains("no way"))
  }
}

struct PipelineStepTests {
  @Test func aPassPutsItsChangesOnTheTabsFields() {
    var base = GenerationFields(prompt: "tab prompt")
    base.parameters.loras = [LoRASelection(file: "tab.ckpt")]
    base.parameters.steps = 20
    let step = PipelineStep(fields: FieldOverlay([.steps: .int(4), .prompt: .text("pass prompt")]))
    let result = step.fields(over: base)
    #expect(result.parameters.steps == 4)
    #expect(result.prompt == "pass prompt")
    #expect(result.parameters.loras.map(\.file) == ["tab.ckpt"])
  }

  @Test func aPassWithLoRAsReplacesTheListAndAnEmptyListClearsIt() {
    var base = GenerationFields()
    base.parameters.loras = [LoRASelection(file: "tab.ckpt")]
    #expect(PipelineStep(loras: [LoRASelection(file: "sun.ckpt", weight: 0.6)]).fields(over: base).parameters.loras.map(\.file) == ["sun.ckpt"])
    #expect(PipelineStep(loras: []).fields(over: base).parameters.loras.isEmpty)
  }
}
