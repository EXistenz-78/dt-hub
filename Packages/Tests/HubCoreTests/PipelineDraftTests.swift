import Foundation
import Testing

@testable import HubCore

struct PipelineDraftTests {
  let a = PipelineDraft.Row.preset("A")
  let b = PipelineDraft.Row.preset("B")

  func draft(_ rows: [PipelineDraft.Row], name: String = "X") -> PipelineDraft {
    var draft = PipelineDraft()
    draft.name = name
    for row in rows { draft.toggle(row) }
    return draft
  }

  @Test func theOrderIsTheOrderOfTheTicks() {
    let draft = draft([b, .current, a])
    #expect(draft.number(of: b) == 1 && draft.number(of: .current) == 2 && draft.number(of: a) == 3)
    #expect(draft.number(of: .preset("C")) == nil)
    #expect(draft.order == [b, .current, a])
  }

  @Test func untickingMovesTheLaterNumbersUp() {
    var draft = draft([b, .current, a])
    draft.toggle(.current)
    #expect(draft.number(of: b) == 1 && draft.number(of: a) == 2 && draft.number(of: .current) == nil)
  }

  @Test func scaleParsing() {
    #expect(PipelineDraft.scale("1,5") == 1.5)
    #expect(PipelineDraft.scale("1.5") == 1.5)
    #expect(PipelineDraft.scale(" 2 ") == 2)
    #expect(PipelineDraft.scale("0,25") == 0.25)
    #expect(PipelineDraft.scale("4") == 4)
    for text in ["", "abc", "0", "5", "-1", "1,5,2", "nan", "inf", "0x10"] { #expect(PipelineDraft.scale(text) == nil, "\(text)") }
  }

  @Test func strengthParsing() {
    #expect(PipelineDraft.strength("") == .automatic)
    #expect(PipelineDraft.strength("  ") == .automatic)
    #expect(PipelineDraft.strength("30") == .value(0.3))
    #expect(PipelineDraft.strength("12,5") == .value(0.125))
    #expect(PipelineDraft.strength("0") == .value(0))
    #expect(PipelineDraft.strength("100") == .value(1))
    for text in ["150", "-1", "abc", "nan"] { #expect(PipelineDraft.strength(text) == .invalid, "\(text)") }
  }

  @Test func theFirstPassAndCurrentSettingsDoNotEditStrength() {
    let draft = draft([a, .current, b])
    #expect([a, .current, b].map(draft.editsScale) == [false, true, true])
    #expect([a, .current, b].map(draft.editsStrength) == [false, false, true])
    #expect(!draft.editsScale(.preset("C")) && !draft.editsStrength(.preset("C")))
  }

  @Test func canSaveNeedsANameTwoPassesAndValidValues() {
    #expect(!draft([a]).canSave)
    #expect(draft([a, b]).canSave)
    #expect(!draft([a, b], name: "a/b").canSave)
    #expect(!draft([a, b], name: "  ").canSave)
    var bad = draft([a, b])
    bad.scaleText[b] = ""
    #expect(!bad.canSave && !bad.isScaleValid(b) && bad.pipeline == nil)
    bad.scaleText[b] = "2"
    bad.strengthText[b] = "150"
    #expect(!bad.canSave && !bad.isStrengthValid(b))
    // A value that is not used does not stop the saving: on the first pass, or on a row that is not ticked.
    var unused = draft([a, b])
    unused.scaleText[a] = "abc"
    unused.strengthText[a] = "abc"
    unused.scaleText[.preset("C")] = ""
    unused.strengthText[.current] = "999"
    #expect(unused.canSave && unused.isScaleValid(a) && unused.isStrengthValid(a))
  }

  @Test func buildsThePipeline() {
    var draft = draft([.current, a, b])
    draft.chain = false
    draft.scaleText[.current] = "3"
    draft.strengthText[.current] = "50"
    draft.scaleText[a] = "2"
    draft.strengthText[b] = "30"
    #expect(
      draft.pipeline
        == UserPipeline(
          chain: false, steps: [.init(preset: nil), .init(preset: "A", scale: 2), .init(preset: "B", scale: 1, strength: 0.3)]))
  }

  @Test func currentSettingsAfterTheFirstPassKeepTheScaleButNotTheStrength() {
    var draft = draft([a, .current])
    draft.scaleText[.current] = "1,5"
    draft.strengthText[.current] = "40"
    #expect(draft.pipeline == UserPipeline(steps: [.init(preset: "A"), .init(preset: nil, scale: 1.5)]))
  }
}
