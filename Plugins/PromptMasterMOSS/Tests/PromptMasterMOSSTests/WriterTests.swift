import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterMOSS

@MainActor
struct WriterTests {
  let data = MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))
  var catalog: MossCatalog { MossCatalog(database: data.database, config: data.config) }
  let options = DTHubLLMOptions(temperature: 0.6, maxTokens: 4096, thinking: false, timeout: 600)

  func item(_ id: Int, _ label: MossLabel, caption: String, text: String = "", tags: String = "") -> MossItem {
    MossItem(id: id, label: label, caption: caption, text: text, tags: tags, colors: [], box: FracBox(x0: 0.1, y0: 0.1, x1: 0.6, y1: 0.6), expanded: false)
  }

  func document() -> MossDocument {
    var document = MossDocument()
    document.description = "una foresta di bambù con una ragazza"
    document.items = [item(1, .panel, caption: "sfondo di bambù"), item(2, .text, caption: "scritta bianca", text: "Kyoto")]
    return document
  }

  /// Un `ask` finto: risponde con le risposte in ordine e ricorda le richieste.
  final class Script: @unchecked Sendable {
    var answers: [DTHubLLMAnswer]
    var requests: [String] = []
    init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
    func next(_ request: String) -> DTHubLLMAnswer {
      requests.append(request)
      return answers.isEmpty ? .failure("no more answers") : answers.removeFirst()
    }
  }

  func writer(_ script: Script) -> MossWriter { MossWriter(ask: { request, _, _ in script.next(request) }, italian: false) }

  static let good =
    "## summary\nA bamboo forest with a girl in a kimono.\n\n## element 1 (panel)\nA dense backdrop of bamboo.\n\n## element 2 (text)\nSmall white lettering."

  @Test func aGoodAnswerRewritesEveryPart() async {
    let script = Script([.text(Self.good)])
    let result = await writer(script).write(document: document(), catalog: catalog, system: "s", options: options)
    #expect(result.rewrites.map(\.kind) == [.summary, .item(id: 1, label: .panel), .item(id: 2, label: .text)])
    #expect(result.rewrites.first?.text == "A bamboo forest with a girl in a kimono.")
    #expect(result.rewrites.first?.original == "una foresta di bambù con una ragazza")
    #expect(result.status == "3 text(s) written.")
    #expect(script.requests.count == 1)
  }

  @Test func theLiteralTextOfATextElementIsNeverSent() async {
    let script = Script([.text(Self.good)])
    let result = await writer(script).write(document: document(), catalog: catalog, system: "s", options: options)
    #expect(!result.request.contains("Kyoto"))
  }

  @Test func translatedQuotedWordsAreRejected_theOriginalStays() async {
    var doc = document()
    doc.items = [item(1, .object, caption: "insegna con \"PIOGGIA\"")]
    doc.description = ""
    let answer = DTHubLLMAnswer.text("## element 1 (object)\nA sign reading \"RAIN\".")
    let script = Script([answer, answer])
    let result = await writer(script).write(document: doc, catalog: catalog, system: "s", options: options)
    #expect(result.rewrites.isEmpty)
    #expect(result.status.contains("element 1 (object)"))
    #expect(script.requests.count == 2)  // la richiesta e il ripiego con la sola parte
  }

  @Test func textThatIsStillItalianIsRetriedWithAReminder() async {
    var doc = MossDocument()
    doc.description = "una ragazza con il kimono"
    let italian = DTHubLLMAnswer.text("## summary\nUna ragazza con il kimono che regge un ombrello sullo sfondo.")
    let english = DTHubLLMAnswer.text("## summary\nA girl in a kimono holding an umbrella.")
    let script = Script([italian, english])
    let result = await writer(script).write(document: doc, catalog: catalog, system: "s", options: options)
    #expect(result.rewrites.map(\.text) == ["A girl in a kimono holding an umbrella."])
    #expect(script.requests.count == 2 && script.requests[1].contains(MossWriter.reminder))
  }

  @Test func aMissingTitleIsRetriedAlone() async {
    let script = Script([.text("## summary\nA bamboo forest."), .text("## element 1 (panel)\nA dense backdrop.")])
    var doc = document()
    doc.items.removeLast()
    let result = await writer(script).write(document: doc, catalog: catalog, system: "s", options: options)
    #expect(result.rewrites.map(\.kind) == [.summary, .item(id: 1, label: .panel)])
    #expect(script.requests[1].contains("## element 1 (panel)") && !script.requests[1].contains("## summary"))
  }

  @Test func aFailureLeavesEverythingAndSaysWhy() async {
    let script = Script([.failure("offline")])
    let result = await writer(script).write(document: document(), catalog: catalog, system: "s", options: options)
    #expect(result.rewrites.isEmpty)
    #expect(result.status.contains("offline"))
  }

  @Test func aFailureAsksOnlyOnce_noRetryPerPart() async {
    let script = Script([.failure("offline")])
    _ = await writer(script).write(document: document(), catalog: catalog, system: "s", options: options)
    #expect(script.requests.count == 1)
  }

  @Test func placeholderAnswersAreRejected_theTextsStay() async {
    let echo = DTHubLLMAnswer.text("## summary\n...\n\n## element 1 (panel)\n...\n\n## element 2 (text)\n...")
    let script = Script([echo, .text("## summary\n..."), .text("## element 1 (panel)\n..."), .text("## element 2 (text)\n...")])
    let result = await writer(script).write(document: document(), catalog: catalog, system: "s", options: options)
    #expect(result.rewrites.isEmpty)
  }

  @Test func nothingToWriteSaysSoAndAsksNothing() async {
    let script = Script([])
    let result = await writer(script).write(document: MossDocument(), catalog: catalog, system: "s", options: options)
    #expect(result.rewrites.isEmpty && result.request.isEmpty && script.requests.isEmpty)
    #expect(result.status == "Nothing to write yet.")
  }

  @Test func guillemetsAndSingleCurlyQuotesProtectWordsToo() {
    #expect(MossCheck.quoted("insegna «Benvenuti» e ‘ciao’") == ["Benvenuti", "ciao"])
    #expect(!MossCheck.preservesQuoted(original: "insegna «Benvenuti»", rewritten: "a sign saying «Welcome»"))
    #expect(MossCheck.preservesQuoted(original: "insegna «Benvenuti»", rewritten: "a sign saying «Benvenuti»"))
  }

  @Test func quotedWordsAreFoundStraightOrCurly() {
    #expect(MossCheck.quoted("a \"uno\" e “due”") == ["uno", "due"])
    #expect(MossCheck.preservesQuoted(original: "sign \"RAIN\"", rewritten: "A sign saying \"RAIN\"."))
    #expect(!MossCheck.preservesQuoted(original: "sign \"RAIN\"", rewritten: "A sign saying \"PIOGGIA\"."))
  }
}
