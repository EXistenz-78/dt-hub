import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterF3

@MainActor
struct PupWriterTests {
  final class Calls {
    var prompts: [String] = []
    var systems: [String] = []
    var options: [DTHubLLMOptions] = []
    var models: [String?] = []
    var answers: [DTHubLLMAnswer]
    init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
  }

  let catalog = F3Catalog(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig)

  func document() -> F3Document {
    var doc = F3Document()
    doc.description = "Una donna con un parasole di carta in una foresta di bambù"
    doc.composition = "Una lanterna <lantern_1> sulla destra e un gatto <cat_1>."
    doc.elements = [
      F3Element(id: "lantern_1", desc: "una lanterna di pietra con muschio", box: BBox(y0: 389, x0: 807, y1: 991, x1: 956), colorIndex: 0, expanded: true),
      F3Element(id: "cat_1", desc: "un gatto nero", box: BBox(y0: 700, x0: 420, y1: 990, x1: 560), colorIndex: 1, expanded: true),
    ]
    return doc
  }

  func writer(_ calls: Calls) -> F3PupWriter {
    F3PupWriter(
      ask: { prompt, system, options, model in
        calls.prompts.append(prompt)
        calls.systems.append(system)
        calls.options.append(options)
        calls.models.append(model)
        return calls.answers.isEmpty ? .failure("No answer.") : calls.answers.removeFirst()
      }, italian: false)
  }

  func run(_ calls: Calls, doc: F3Document? = nil) async -> F3PupResult {
    await writer(calls).write(document: doc ?? document(), terms: [], model: "pup", systemPrompt: "SYSTEM")
  }

  @Test func theProseIsTheDescriptionPlusTheTermsPlusTheComposition() {
    let prose = F3Composer.prose(description: "A woman", terms: ["Golden hour", "Film grain"], composition: "Near <lamp_1>.")
    #expect(prose == "A woman Golden hour, Film grain.\n\nNear <lamp_1>.")
    #expect(F3Composer.text(description: "A woman", terms: ["Golden hour", "Film grain"], composition: "Near <lamp_1>.", elements: []).hasPrefix(prose))
  }

  @Test func aGoodAnswerGivesTheCaptionTheDescsAndTheAddedRows() async throws {
    let calls = Calls([.text(try PupFixture.text("pup_t2i.txt"))])
    let result = await run(calls)
    #expect(result.succeeded)
    #expect(result.caption?.contains("<lantern_1>") == true && result.caption?.contains("<person_1>") == true)
    #expect(result.descriptions["lantern_1"]?.hasPrefix("A tall weathered stone lantern") == true)
    #expect(result.addedRows.map(\.id) == ["parasol_1", "person_1", "forest_1"])
  }

  @Test func theCallCarriesTheModelTheSystemPromptTheLockedRowsAndTheOptions() async throws {
    let calls = Calls([.text(try PupFixture.text("pup_t2i.txt"))])
    _ = await run(calls)
    #expect(calls.models == ["pup"] && calls.systems == ["SYSTEM"] && calls.options == [F3PupRequest.options])
    #expect(calls.prompts[0].hasPrefix("ORIGINAL PROMPT:\nUna donna con un parasole"))
    #expect(calls.prompts[0].contains(#"{"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "una lanterna di pietra con muschio"}"#))
  }

  @Test func aMissingCitationTriggersOneRetryWithTheReminder() async throws {
    let bad = #"A scene. [{"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "A lantern."}, {"id": "cat_1", "bbox": [700, 420, 990, 560], "desc": "A cat."}]"#
    let calls = Calls([.text(bad), .text(try PupFixture.text("pup_t2i.txt"))])
    let result = await run(calls)
    #expect(result.succeeded && calls.prompts.count == 2)
    #expect(!calls.prompts[0].contains(F3Writer.idReminder) && calls.prompts[1].hasSuffix(F3Writer.idReminder))
  }

  @Test func aChangedQuoteIsRejected() async throws {
    var doc = document()
    doc.composition = #"Una lanterna <lantern_1> con un cartello "APERTO" e un gatto <cat_1>."#
    let calls = Calls([.text(try PupFixture.text("pup_t2i.txt")), .text(try PupFixture.text("pup_t2i.txt"))])
    let result = await run(calls, doc: doc)
    #expect(!result.succeeded && calls.prompts.count == 2)
  }

  @Test func anAnswerWithoutAListOrWithAnUnknownPlaceholderOrInItalianIsRejected() async {
    let row = #"[{"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "A lantern."}, {"id": "cat_1", "bbox": [700, 420, 990, 560], "desc": "A cat."}]"#
    for text in [
      "A <lantern_1> and a <cat_1>.", "A <lantern_1> and a <cat_1> near <tree_9>. " + row,
      "Una lanterna <lantern_1> con il gatto <cat_1> sul lato della foresta di bambù e la donna. " + row,
    ] {
      let calls = Calls([.text(text), .text(text)])
      let result = await run(calls)
      #expect(!result.succeeded && calls.prompts.count == 2, Comment(rawValue: text))
    }
  }

  @Test func aModelFailureGivesItsReasonAndNoRetry() async {
    let calls = Calls([.failure("No model chosen.")])
    let result = await run(calls)
    #expect(!result.succeeded && result.status == "No model chosen." && calls.prompts.count == 1)
  }

  @Test func withoutElementsTheModelIsNotAsked() async {
    let calls = Calls([.text("x")])
    var doc = document()
    doc.elements = []
    let result = await run(calls, doc: doc)
    #expect(!result.succeeded && calls.prompts.isEmpty)
  }
}
