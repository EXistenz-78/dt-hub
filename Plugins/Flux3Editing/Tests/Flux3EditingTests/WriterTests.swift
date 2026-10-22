import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct WriterTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }

  private func document() -> EditDocument {
    var doc = EditDocument()
    doc.prose = "Modifica <ref_image_0> aggiungendo <lamp_1> da <ref_image_1>."
    doc.draw(onReference: "a.png", box: box(100, 100, 400, 400))
    doc.elements[0].id = "lamp_1"
    doc.elements[0].desc = "una lampada d'ottone"
    return doc
  }

  private let allowed: Set<String> = ["ref_image_0", "ref_image_1", "lamp_1"]
  private let options = DTHubLLMOptions()

  private func writer(_ answers: [DTHubLLMAnswer], log: Log = Log()) -> EditWriter {
    var queue = answers
    return EditWriter(ask: { request, _, _ in
      log.requests.append(request)
      return queue.isEmpty ? .failure("No answer.") : queue.removeFirst()
    }, italian: false)
  }

  final class Log { var requests: [String] = [] }

  @Test func theRequestIsMarkdownWithOneBlockPerPart() async {
    let log = Log()
    _ = await writer([.text("## prose\nModify <ref_image_0> by adding <lamp_1> from <ref_image_1>.\n\n## element: lamp_1\nA brass table lamp.")], log: log)
      .write(document: document(), allowedTags: allowed, system: "S", options: options)
    let request = log.requests[0]
    #expect(request.contains("## prose\nModifica <ref_image_0>") && request.contains("## element: lamp_1\nuna lampada d'ottone"))
  }

  @Test func aGoodAnswerRewritesBothParts() async {
    let result = await writer([.text("## prose\nModify <ref_image_0> by adding <lamp_1> from <ref_image_1>.\n\n## element: lamp_1\nA brass table lamp.")])
      .write(document: document(), allowedTags: allowed, system: "S", options: options)
    #expect(result.rewrites.map(\.text) == ["Modify <ref_image_0> by adding <lamp_1> from <ref_image_1>.", "A brass table lamp."])
  }

  @Test func theProseMayGainACitationOfAnElementButNeverLoseOne() async {
    var doc = document()
    doc.prose = "Add the lamp from <ref_image_1>."
    let good = await writer([.text("## prose\nAdd the lamp <lamp_1> from <ref_image_1>.\n\n## element: lamp_1\nA brass lamp.")])
      .write(document: doc, allowedTags: allowed, system: "S", options: options)
    #expect(good.rewrites.contains { $0.kind == .prose })
    // The original cites <ref_image_1>: dropping it is not acceptable (twice: the retry fails too).
    let lost = await writer([
      .text("## prose\nAdd the lamp.\n\n## element: lamp_1\nA brass lamp."), .text("## prose\nAdd the lamp.")
    ]).write(document: doc, allowedTags: allowed, system: "S", options: options)
    #expect(!lost.rewrites.contains { $0.kind == .prose })
  }

  @Test func anInventedTagIsRefused() async {
    let result = await writer([
      .text("## prose\nModify <ref_image_0> adding <lamp_1> and <ghost_9>.\n\n## element: lamp_1\nA lamp."),
      .text("## prose\nModify <ref_image_0> adding <lamp_1> and <ghost_9>."),
    ]).write(document: document(), allowedTags: allowed, system: "S", options: options)
    #expect(!result.rewrites.contains { $0.kind == .prose } && result.rewrites.contains { $0.kind == .element(id: "lamp_1") })
  }

  @Test func anElementDescriptionMustNotGetPlaceholders() async {
    let result = await writer([
      .text("## prose\nModify <ref_image_0> by adding <lamp_1> from <ref_image_1>.\n\n## element: lamp_1\nA lamp <lamp_1>."),
      .text("## element: lamp_1\nA lamp <lamp_1>."),
    ]).write(document: document(), allowedTags: allowed, system: "S", options: options)
    #expect(!result.rewrites.contains { $0.kind == .element(id: "lamp_1") })
  }

  @Test func textThatStaysItalianIsRetriedOnceThenKeptAsItWas() async {
    let italian = "## prose\nModifica <ref_image_0> con la lampada <lamp_1> da <ref_image_1>.\n\n## element: lamp_1\nA brass lamp."
    let log = Log()
    let result = await writer([.text(italian), .text("## prose\nModifica <ref_image_0> con la lampada <lamp_1> da <ref_image_1>.")], log: log)
      .write(document: document(), allowedTags: allowed, system: "S", options: options)
    #expect(log.requests.count == 2 && log.requests[1].contains("IMPORTANT"))
    #expect(!result.rewrites.contains { $0.kind == .prose })
    #expect(result.status.contains("prose"))
  }

  @Test func aFailedAskSaysWhyAndChangesNothing() async {
    let result = await writer([.failure("No model chosen.")]).write(document: document(), allowedTags: allowed, system: "S", options: options)
    #expect(result.rewrites.isEmpty && result.status.contains("No model chosen."))
  }

  @Test func quotedWordsMustBeCopiedExactly() async {
    var doc = document()
    doc.elements[0].desc = "un cartello con la scritta \"APERTO\""
    let result = await writer([
      .text("## prose\nModify <ref_image_0> by adding <lamp_1> from <ref_image_1>.\n\n## element: lamp_1\nA sign saying \"open\"."),
      .text("## element: lamp_1\nA sign saying \"open\"."),
    ]).write(document: doc, allowedTags: allowed, system: "S", options: options)
    #expect(!result.rewrites.contains { $0.kind == .element(id: "lamp_1") })
  }

  @Test func nothingToWriteMakesNoRequest() async {
    let log = Log()
    let result = await writer([], log: log).write(document: EditDocument(), allowedTags: [], system: "S", options: options)
    #expect(log.requests.isEmpty && result.rewrites.isEmpty && !result.status.isEmpty)
  }

  @Test func applyingARewriteKeepsWhatTheUserChangedMeanwhile() async throws {
    let state = EditState(store: EditStore(storage: MemoryStorage()), italian: false, imageSize: { _ in nil })
    state.document = document()
    let result = await writer([.text("## prose\nModify <ref_image_0> by adding <lamp_1> from <ref_image_1>.\n\n## element: lamp_1\nA brass table lamp.")])
      .write(document: state.document, allowedTags: allowed, system: "S", options: options)
    state.update(element: "lamp_1") { $0.desc = "edited by hand while the LLM wrote" }
    state.apply(result)
    #expect(state.document.prose == "Modify <ref_image_0> by adding <lamp_1> from <ref_image_1>.")
    #expect(state.document.elements[0].desc == "edited by hand while the LLM wrote")
    #expect(state.canUndo)
    state.undo()
    #expect(state.document.prose == "Modifica <ref_image_0> aggiungendo <lamp_1> da <ref_image_1>.")
  }
}
