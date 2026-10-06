import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterI4

@MainActor
@Suite("Writing with the language model")
struct WriterTests {
  private let catalog = I4Catalog(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig)

  /// A language model that answers from a script and remembers what it was asked.
  @MainActor final class Script {
    var answers: [DTHubLLMAnswer]
    private(set) var prompts: [String] = []
    private(set) var systems: [String] = []
    private(set) var options: [DTHubLLMOptions] = []
    init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
    func next(_ prompt: String, _ system: String, _ options: DTHubLLMOptions) -> DTHubLLMAnswer {
      prompts.append(prompt)
      systems.append(system)
      self.options.append(options)
      return answers.isEmpty ? .failure("No more answers.") : answers.removeFirst()
    }
  }

  private func document() -> I4Document {
    var document = I4Document()
    document.description = "due amici"
    document.choose("ls_neon", catalog: catalog)
    let id = document.addElement(type: .obj)
    document.updateElement(id) { $0.desc = "una tazza" }
    return document
  }

  private func write(_ document: I4Document, _ script: Script, progress: @escaping @MainActor (String) -> Void = { _ in }) async -> I4Writer.Outcome {
    let writer = I4Writer(ask: { script.next($0, $1, $2) }, italian: false, progress: progress)
    let fields = document.fields(catalog: catalog)
    return await writer.write(
      targets: fields.filter(\.needsWriting), fields: fields, system: "SYSTEM", options: DTHubLLMOptions(temperature: 0.6, maxTokens: 4096))
  }

  private let all = DTHubLLMAnswer.text(
    "<high_level_description>Two friends.</high_level_description><lighting>Neon light.</lighting><element_1 kind=\"object\">A cup.</element_1>")

  @Test func everyFieldInOneRequestWithTheSystemPromptAndTheOptions() async {
    let doc = document()
    let script = Script([all])
    let outcome = await write(doc, script)
    #expect(script.prompts.count == 1 && script.systems == ["SYSTEM"] && script.options[0].maxTokens == 4096)
    #expect(script.prompts[0].contains("<high_level_description>") && script.prompts[0].contains("<element_1 kind=\"object\">"))
    #expect(outcome.phrases.keys.sorted() == ["description", "element:1", "lighting"] && outcome.failed.isEmpty)
    #expect(outcome.phrases["description"] == WrittenPhrase(text: "Two friends.", input: "due amici"))
    #expect(outcome.phrases["element:1"]?.input == "object\nuna tazza")
    #expect(outcome.status == "3 sentence(s) written.")
  }

  @Test func aFieldTheAnswerLacksGetsARequestOfItsOwnThatKnowsTheOthers() async {
    let script = Script([
      .text("<high_level_description>Two friends.</high_level_description><lighting>Neon light.</lighting>"),
      .text("<element_1>A cup.</element_1>"),
    ])
    var told: [String] = []
    let outcome = await write(document(), script) { told.append($0) }
    #expect(script.prompts.count == 2 && told == ["Writing… field 1 of 1"])
    let second = script.prompts[1]
    #expect(second.hasPrefix("<element_1 kind=\"object\">\nuna tazza\n</element_1>") && !second.contains("<lighting>\nLight Source"))
    #expect(second.contains("<already_written>") && second.contains("high_level_description: Two friends.") && second.contains("lighting: Neon light."))
    #expect(outcome.phrases.count == 3 && outcome.failed.isEmpty)
  }

  @Test func anAnswerWithoutTagsGivesOneRequestPerFieldAndTheWholeAnswerWhenOneFieldIsAsked() async {
    var doc = I4Document()
    doc.description = "una scena"
    let single = await write(doc, Script([.text("A scene.")]))
    #expect(single.phrases["description"]?.text == "A scene." && single.failed.isEmpty)
    let script = Script([.text("no tags at all"), .text("<high_level_description>Two friends.</high_level_description>"), .text("<lighting>Neon.</lighting>")])
    var doc2 = I4Document()
    doc2.description = "due amici"
    doc2.choose("ls_neon", catalog: catalog)
    let outcome = await write(doc2, script) { _ in }
    #expect(script.prompts.count == 3 && outcome.phrases.count == 2)
  }

  @Test func aFieldThatFailsAloneStaysRawAndIsNamedWhileTheOthersAreKept() async {
    let script = Script([.text("<high_level_description>Two friends.</high_level_description>"), .text("<lighting>oops</wrong>"), .text("<element_1>A cup.</element_1>")])
    let outcome = await write(document(), script)
    #expect(outcome.phrases.keys.sorted() == ["description", "element:1"] && outcome.failed == ["Lighting"])
    #expect(outcome.status == "2 sentence(s) written. No sentence for: Lighting (the raw text stays).")
  }

  @Test func ifTheAppRefusesTwiceInARowItStopsInsteadOfAskingForEveryField() async {
    let script = Script([.failure("No language model chosen."), .failure("No language model chosen."), .failure("never asked")])
    let outcome = await write(document(), script)
    #expect(script.prompts.count == 2 && outcome.phrases.isEmpty)
    #expect(outcome.failed == ["High level description", "Lighting", "E1 · obj"])
    #expect(outcome.status == "No language model chosen.")
  }

  @Test func aRequestThatFailsOnceButWhoseFieldsAnswerAloneStillWorks() async {
    let script = Script([.failure("Timeout."), .text("<high_level_description>A.</high_level_description>"), .text("<lighting>B.</lighting>"), .text("<element_1>C.</element_1>")])
    let outcome = await write(document(), script)
    #expect(script.prompts.count == 4 && outcome.phrases.count == 3 && outcome.failed.isEmpty)
  }

  @Test func theInputIsTheOneOfTheRequestEvenIfTheFieldChangesWhileTheModelWrites() async {
    var doc = I4Document()
    doc.description = "prima"
    let fields = doc.fields(catalog: catalog)
    let script = Script([.text("<high_level_description>First.</high_level_description>")])
    let writer = I4Writer(ask: { script.next($0, $1, $2) }, italian: false)
    let outcome = await writer.write(targets: fields.filter(\.needsWriting), fields: fields, system: "S", options: DTHubLLMOptions())
    doc.description = "dopo"  // the user went on typing
    doc.written.merge(outcome.phrases) { _, new in new }
    #expect(doc.fields(catalog: catalog).first { $0.id == "description" }?.state == .stale)
  }

  @Test func nothingToWriteMeansNoRequest() async {
    let script = Script([all])
    let outcome = await write(I4Document(), script)
    #expect(script.prompts.isEmpty && outcome == I4Writer.Outcome())
  }
}
