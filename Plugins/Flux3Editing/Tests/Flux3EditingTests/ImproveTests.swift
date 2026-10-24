import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct ImproveTests {
  final class Calls {
    var models: [String?] = []
    var systems: [String] = []
    var images: [[String]] = []
    var answers: [DTHubLLMAnswer]
    init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
  }

  private let ref = RefImage(number: 1, path: "/s/ninja.png", size: CGSize(width: 446, height: 448))
  private let pup = [EditPicture(number: 0, role: .start, path: "/t/0.jpg"), EditPicture(number: 1, role: .reference, path: "/t/1.jpg")]
  private let drawn = [EditPicture(number: 0, role: .start, path: "/t/drawn-0.png"), EditPicture(number: 1, role: .reference, path: "/t/drawn-1.png")]
  private let standardAnswer = DTHubLLMAnswer.text(
    "## prose\nModify <ref_image_0> by adding the ninja warrior <el_2> from <ref_image_1>.\n\n## element: el_2\nA ninja warrior in black gear.")

  private func document() -> EditDocument {
    var doc = EditDocument()
    doc.prose = "Modify <ref_image_0> by: adding a ninja <el_2> from <ref_image_1>"
    doc.elements = [
      EditElement(
        id: "el_2", colorIndex: 0, kind: .fromReference, refFile: "ninja.png", src: BBox(y0: 78, x0: 92, y1: 974, x1: 950),
        tgt: BBox(y0: 488, x0: 67, y1: 952, x1: 379), desc: "un ninja")
    ]
    return doc
  }

  private func improver(_ calls: Calls) -> EditImprover {
    EditImprover(
      ask: { _, system, _, images, model in
        calls.systems.append(system)
        calls.images.append(images)
        calls.models.append(model)
        return calls.answers.isEmpty ? .failure("No answer.") : calls.answers.removeFirst()
      }, italian: false)
  }

  private func run(_ calls: Calls, mode: WriteMode, pupPictures: [EditPicture]? = nil) async -> EditImproveOutcome {
    await improver(calls).improve(
      document: document(), refs: [ref], allowedTags: ["el_2", "ref_image_0", "ref_image_1"], mode: mode, pupPictures: pupPictures ?? pup,
      drawnPictures: drawn, standardSystem: "STANDARD")
  }

  @Test func pupModeUsesTheRawPicturesAndNamesTheModel() async throws {
    let calls = Calls([.text(try PupFixture.text("pup_blur.txt"))])
    let outcome = await run(calls, mode: .pup(name: "pup", systemPrompt: "SYSTEM"))
    #expect(outcome.pup?.succeeded == true && outcome.standard == nil)
    #expect(calls.models == ["pup"] && calls.systems == ["SYSTEM"] && calls.images == [["/t/0.jpg", "/t/1.jpg"]])
    #expect(outcome.note == "Improved with pup (PUP mode).")
  }

  @Test func standardModeAsksTheChosenModelWithTheDrawnPictures() async {
    let calls = Calls([standardAnswer])
    let outcome = await run(calls, mode: .standard(model: "qwen"))
    #expect(outcome.pup == nil && outcome.standard?.rewrites.isEmpty == false)
    #expect(calls.models == ["qwen"] && calls.systems.first == "STANDARD" && calls.images.first == ["/t/drawn-0.png", "/t/drawn-1.png"])
    #expect(outcome.note == "Improved with qwen (standard mode).")
  }

  @Test func standardModeWithoutAKnownModelAsksTheAppsChoice() async {
    let calls = Calls([standardAnswer])
    let outcome = await run(calls, mode: .standard(model: nil))
    #expect(calls.models == [nil] && outcome.note == "Improved (standard mode).")
  }

  @Test func aPupFailureFallsBackToStandardWithTheSameModel() async {
    let calls = Calls([.text("nothing"), .text("nothing again"), standardAnswer])
    let outcome = await run(calls, mode: .pup(name: "pup", systemPrompt: "SYSTEM"))
    #expect(outcome.pup == nil && outcome.standard?.rewrites.isEmpty == false)
    #expect(calls.models == ["pup", "pup", "pup"] && calls.systems.last == "STANDARD")
    #expect(outcome.note == "Improved with pup (standard mode).")
  }

  @Test func withoutPupPicturesTheModelGoesStraightToStandard() async {
    let calls = Calls([standardAnswer])
    let outcome = await run(calls, mode: .pup(name: "pup", systemPrompt: "SYSTEM"), pupPictures: [])
    #expect(calls.systems == ["STANDARD"] && calls.models == ["pup"] && outcome.standard != nil)
  }

  @Test func whenNothingIsWrittenThereIsNoNote() async {
    let calls = Calls([.failure("No model chosen.")])
    let outcome = await run(calls, mode: .standard(model: nil))
    #expect(outcome.note.isEmpty)
  }
}
