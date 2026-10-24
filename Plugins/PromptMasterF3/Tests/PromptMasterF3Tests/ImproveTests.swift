import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterF3

@MainActor
struct ImproveTests {
  final class Calls {
    var models: [String?] = []
    var systems: [String] = []
    var prompts = 0
    var answers: [DTHubLLMAnswer]
    init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
  }

  let catalog = F3Catalog(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig)
  let pupMode = F3WriteMode.pup(name: "pup", systemPrompt: "SYSTEM")
  let standardAnswer = DTHubLLMAnswer.text("## description\nA woman with a paper parasol in a bamboo forest.\n\n## composition\nA stone lantern <lantern_1> on the right and a black cat <cat_1>.\n\n## element: lantern_1\nA stone lantern.\n\n## element: cat_1\nA black cat.")

  func document() -> F3Document { PupWriterTests().document() }

  func run(_ calls: Calls, mode: F3WriteMode) async -> F3ImproveOutcome {
    await F3Improver(
      ask: { _, system, _, model in
        calls.prompts += 1
        calls.systems.append(system)
        calls.models.append(model)
        return calls.answers.isEmpty ? .failure("No answer.") : calls.answers.removeFirst()
      }, italian: false
    ).improve(document: document(), catalog: catalog, mode: mode, standardSystem: "STANDARD", standardOptions: DTHubLLMOptions())
  }

  @Test func pupModeSucceedsAndNamesTheModel() async throws {
    let calls = Calls([.text(try PupFixture.text("pup_t2i.txt"))])
    let outcome = await run(calls, mode: pupMode)
    #expect(outcome.pup?.succeeded == true && outcome.standard == nil)
    #expect(calls.models == ["pup"] && calls.systems == ["SYSTEM"] && outcome.note == "Improved with pup (PUP mode).")
  }

  @Test func standardModeAsksTheChosenModelWithTheMasterPrompt() async {
    let calls = Calls([standardAnswer])
    let outcome = await run(calls, mode: .standard(model: "qwen"))
    #expect(outcome.pup == nil && outcome.standard?.rewrites.isEmpty == false)
    #expect(calls.models.first == "qwen" && calls.systems.first == "STANDARD" && outcome.note == "Improved with qwen (standard mode).")
    let unnamed = Calls([standardAnswer])
    #expect(await run(unnamed, mode: .standard(model: nil)).note == "Improved (standard mode).")
    #expect(unnamed.models == [nil])
  }

  @Test func aPupThatCannotWriteLeavesTheTextsAndSaysWhy() async {
    let failing = Calls([.failure("The model was loaded without its vision part")])
    let outcome = await run(failing, mode: pupMode)
    #expect(outcome.standard?.rewrites.isEmpty == true && outcome.standard?.status.contains("vision part") == true && failing.prompts == 1)
    let unusable = Calls([.text("nothing"), .text("again")])
    let second = await run(unusable, mode: pupMode)
    #expect(second.standard?.status.contains("pup") == true && unusable.systems == ["SYSTEM", "SYSTEM"] && second.note.isEmpty)
  }
}
