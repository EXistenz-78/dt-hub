import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterF3

final class ScriptedLLM: @unchecked Sendable {
  private let lock = NSLock()
  private var answers: [DTHubLLMAnswer]
  private(set) var requests: [String] = []
  init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
  func next(_ prompt: String) -> DTHubLLMAnswer {
    lock.lock()
    defer { lock.unlock() }
    requests.append(prompt)
    return answers.isEmpty ? .failure("no more answers") : answers.removeFirst()
  }
}

struct WriterTests {
  let catalog = F3Catalog(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig)

  func document() -> F3Document {
    var document = F3Document()
    document.description = "una strada piovosa"
    document.composition = "Una donna <woman_1> con un ombrello <umbrella_1>."
    let box = BBox(y0: 0, x0: 0, y1: 100, x1: 100)
    document.elements = [
      F3Element(id: "woman_1", desc: "donna con trench", box: box, colorIndex: 0, expanded: false),
      F3Element(id: "umbrella_1", desc: "ombrello rosso con scritta \"RAIN\"", box: box, colorIndex: 1, expanded: false),
    ]
    return document
  }

  func writer(_ llm: ScriptedLLM) -> F3Writer { F3Writer(ask: { prompt, _, _ in llm.next(prompt) }, italian: false) }

  func run(_ llm: ScriptedLLM) async -> F3WriteResult {
    await writer(llm).write(document: document(), catalog: catalog, system: "S", options: DTHubLLMOptions())
  }

  let good = """
    ## description
    A rainy street at night.

    ## composition
    A woman <woman_1> holds an umbrella <umbrella_1> in the rain.

    ## element: woman_1
    A woman in a black trench coat.

    ## element: umbrella_1
    A red umbrella printed with "RAIN".
    """

  @Test func goodAnswerGivesAllFourRewritesInOneRequest() async {
    let llm = ScriptedLLM([.text(good)])
    let result = await run(llm)
    #expect(llm.requests.count == 1)
    #expect(result.rewrites.map(\.kind) == [.description, .composition, .element(id: "woman_1"), .element(id: "umbrella_1")])
    #expect(result.rewrites[0].original == "una strada piovosa")
    #expect(result.rewrites[1].text.contains("<woman_1>"))
    #expect(result.status == "4 text(s) written.")
  }

  @Test func changedIDInCompositionIsRetriedAloneThenKeptOriginal() async {
    let broken = good.replacingOccurrences(of: "<umbrella_1> in the rain", with: "<umbrella_2> in the rain")
    let llm = ScriptedLLM([.text(broken), .text("A woman <woman_1> holds an umbrella <umbrella_9>.")])
    let result = await run(llm)
    #expect(llm.requests.count == 2)
    #expect(llm.requests[1].contains(F3Writer.idReminder))
    #expect(!result.rewrites.contains { $0.kind == .composition })
    #expect(result.rewrites.count == 3)
    #expect(result.status.contains("the LLM changed the ids of the composition"))
  }

  @Test func retryCanFixTheComposition() async {
    let broken = good.replacingOccurrences(of: "<woman_1> holds", with: "<woman_2> holds")
    let llm = ScriptedLLM([.text(broken), .text("## composition\nA woman <woman_1> and an umbrella <umbrella_1>.")])
    let result = await run(llm)
    #expect(result.rewrites.first { $0.kind == .composition }?.text == "A woman <woman_1> and an umbrella <umbrella_1>.")
  }

  @Test func missingIDOrExtraIDIsRejected() {
    #expect(!F3IDCheck.preserves(original: "A <a> and <b>.", rewritten: "A <a>."))
    #expect(!F3IDCheck.preserves(original: "A <a>.", rewritten: "A <a> and <b>."))
    #expect(!F3IDCheck.preserves(original: "A <a> and <a>.", rewritten: "A <a>."))
    #expect(F3IDCheck.preserves(original: "A <a> and <b>.", rewritten: "Una <b> e <a>."))
  }

  @Test func quotedWordsMustStayInTheDesc() async {
    let broken = good.replacingOccurrences(of: "printed with \"RAIN\"", with: "printed with \"PLUIE\"")
    let llm = ScriptedLLM([.text(broken), .text("## element: umbrella_1\nA red umbrella with the word \"PLUIE\".")])
    let result = await run(llm)
    #expect(!result.rewrites.contains { $0.kind == .element(id: "umbrella_1") })
    #expect(result.rewrites.count == 3)
  }

  @Test func missingPartFallsBackToASingleRequest() async {
    let withoutWoman = good.replacingOccurrences(of: "## element: woman_1\nA woman in a black trench coat.\n\n", with: "")
    let llm = ScriptedLLM([.text(withoutWoman), .text("A woman in a trench coat.")])
    let result = await run(llm)
    #expect(llm.requests.count == 2)
    #expect(result.rewrites.first { $0.kind == .element(id: "woman_1") }?.text == "A woman in a trench coat.")
  }

  @Test func descriptionMayNotInventPlaceholders() async {
    let broken = good.replacingOccurrences(of: "A rainy street at night.", with: "A rainy street <x_1> at night.")
    let llm = ScriptedLLM([.text(broken), .text("## description\nStill <x_1>.")])
    let result = await run(llm)
    #expect(!result.rewrites.contains { $0.kind == .description })
  }

  @Test func failureLeavesNothingAndSaysWhy() async {
    let llm = ScriptedLLM([.failure("model not loaded"), .failure("model not loaded"), .failure("x"), .failure("x"), .failure("x")])
    let result = await run(llm)
    #expect(result.rewrites.isEmpty)
    #expect(result.status.contains("model not loaded"))
  }

  @Test func nothingToWriteMakesNoRequest() async {
    let llm = ScriptedLLM([])
    let result = await writer(llm).write(document: F3Document(), catalog: catalog, system: "S", options: DTHubLLMOptions())
    #expect(llm.requests.isEmpty)
    #expect(result.status == "Nothing to write yet.")
  }
}
