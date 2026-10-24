import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct PupWriterTests {
  final class Calls {
    var prompts: [String] = []
    var systems: [String] = []
    var options: [DTHubLLMOptions] = []
    var images: [[String]] = []
    var models: [String] = []
    var answers: [DTHubLLMAnswer]
    init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
  }

  private let ref = RefImage(number: 1, path: "/s/ninja.png", size: CGSize(width: 446, height: 448))
  private let pictures = [
    EditPicture(number: 0, role: .start, path: "/t/0.jpg"), EditPicture(number: 1, role: .reference, path: "/t/1.jpg"),
  ]

  private func document(prose: String = "Modify <ref_image_0> by: adding a ninja warrior <el_2> from <ref_image_1>.") -> EditDocument {
    var doc = EditDocument()
    doc.prose = prose
    doc.elements = [
      EditElement(
        id: "el_2", colorIndex: 0, kind: .fromReference, refFile: "ninja.png", src: BBox(y0: 78, x0: 92, y1: 974, x1: 950),
        tgt: BBox(y0: 488, x0: 67, y1: 952, x1: 379), desc: "un nninja che si muove tra i bamboo")
    ]
    return doc
  }

  private func writer(_ calls: Calls) -> EditPupWriter {
    EditPupWriter(
      ask: { prompt, system, options, images, model in
        calls.prompts.append(prompt)
        calls.systems.append(system)
        calls.options.append(options)
        calls.images.append(images)
        calls.models.append(model)
        return calls.answers.isEmpty ? .failure("No answer.") : calls.answers.removeFirst()
      }, italian: false)
  }

  private func run(_ calls: Calls, doc: EditDocument? = nil) async -> EditPupResult {
    await writer(calls).write(document: doc ?? document(), refs: [ref], pictures: pictures, model: "pup", systemPrompt: "SYSTEM")
  }

  @Test func aGoodAnswerGivesProseDescriptionsAndExtraRows() async throws {
    let calls = Calls([.text(try PupFixture.text("pup_blur.txt"))])
    let result = await run(calls)
    #expect(result.succeeded)
    #expect(result.prose?.contains("<el_2>") == true && result.prose?.contains("<ninja_1>") == false)
    #expect(result.descriptions["el_2"]?.hasPrefix("An adult male ninja warrior") == true)
    #expect(result.extraRows.map(\.id) == ["person_1"])
    #expect(calls.prompts.count == 1)
  }

  @Test func everyCallCarriesTheModelTheSystemPromptThePicturesAndTheOptions() async throws {
    let calls = Calls([.text(try PupFixture.text("pup_blur.txt"))])
    _ = await run(calls)
    #expect(calls.models == ["pup"] && calls.systems == ["SYSTEM"] && calls.images == [["/t/0.jpg", "/t/1.jpg"]])
    #expect(calls.options == [PupRequest.options])
    #expect(calls.prompts[0].contains("LOCKED BOUNDING-BOX ANNOTATIONS") && calls.prompts[0].contains(#""from":"ref_image_1""#))
  }

  @Test func aMissingCitationTriggersOneRetryWithTheReminder() async throws {
    let bad = #"Add a ninja somewhere. [{"id":"el_2","from":"ref_image_1","src_bbox":[78,92,974,950],"tgt_bbox":[488,67,952,379],"desc":"A ninja"}]"#
    let calls = Calls([.text(bad), .text(try PupFixture.text("pup_sharp.txt"))])
    let result = await run(calls)
    #expect(result.succeeded && calls.prompts.count == 2)
    #expect(!calls.prompts[0].contains(EditWriter.reminder) && calls.prompts[1].contains(EditWriter.reminder))
  }

  @Test func aChangedQuoteIsRejected() async throws {
    let doc = document(prose: #"Modify <ref_image_0> by adding <el_2> and a sign "APERTO"."#)
    let calls = Calls([.text(try PupFixture.text("pup_blur.txt")), .text(try PupFixture.text("pup_blur.txt"))])
    let result = await run(calls, doc: doc)
    #expect(!result.succeeded && calls.prompts.count == 2)
  }

  @Test func anItalianAnswerIsRejected() async {
    let italian = #"Aggiungi il ninja <el_2> con il suo costume nero dentro il bosco di bambù, sul lato della ragazza. [{"id":"el_2","from":"ref_image_1","src_bbox":[78,92,974,950],"tgt_bbox":[488,67,952,379],"desc":"un ninja che si muove tra i bambù"}]"#
    let calls = Calls([.text(italian), .text(italian)])
    let result = await run(calls)
    #expect(!result.succeeded && calls.prompts.count == 2)
  }

  @Test func twoFailuresGiveNoTexts() async {
    let calls = Calls([.text("nothing useful"), .text("still nothing")])
    let result = await run(calls)
    #expect(!result.succeeded && result.prose == nil && result.descriptions.isEmpty && result.extraRows.isEmpty)
  }

  @Test func aFailureOfTheModelGivesItsReasonAndNoRetry() async {
    let calls = Calls([.failure("No model chosen.")])
    let result = await run(calls)
    #expect(!result.succeeded && result.status == "No model chosen." && calls.prompts.count == 1)
  }

  @Test func withoutPicturesTheModelIsNotAsked() async {
    let calls = Calls([.text("x")])
    let result = await writer(calls).write(document: document(), refs: [ref], pictures: [], model: "pup", systemPrompt: "SYSTEM")
    #expect(!result.succeeded && calls.prompts.isEmpty)
  }
}
