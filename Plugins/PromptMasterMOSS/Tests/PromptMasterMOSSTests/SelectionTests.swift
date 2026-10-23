import Foundation
import Testing

@testable import PromptMasterMOSS

@MainActor
struct SelectionTests {
  static let data = MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))

  func state() -> MossState {
    let state = MossState(
      data: Self.data,
      promptFolder: MossPrompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-sel-\(UUID().uuidString)")),
      store: MossStore(storage: MemoryStorage()), italian: false, shuffler: { _, _ in [] })
    state.update(generationSize: PixelSize(width: 1024, height: 640))
    return state
  }

  func term(_ category: String, _ index: Int) -> String { Self.data.database.categories.first { $0.id == category }!.terms[index].id }

  @Test func chooseKeepsOneTermPerCategoryAndTogglesOff() {
    let state = state()
    state.choose(term("light_source", 0))
    state.choose(term("light_quality", 0))
    #expect(state.document.selection == [term("light_source", 0), term("light_quality", 0)])
    state.choose(term("light_source", 1))
    #expect(state.document.selection == [term("light_source", 1), term("light_quality", 0)])
    state.choose(term("light_source", 1))
    #expect(state.document.selection == [term("light_quality", 0)])
  }

  @Test func negativeTermsAreMultipleChoice() {
    let state = state()
    state.document.negativeSelection = []
    state.toggleNegative("ng_blurry")
    state.toggleNegative("ng_ugly")
    #expect(state.document.negativeSelection == ["ng_blurry", "ng_ugly"])
    state.toggleNegative("ng_blurry")
    #expect(state.document.negativeSelection == ["ng_ugly"])
  }

  @Test func freeMetaTagsAreTrimmedWithoutEmptiesOrDuplicates() {
    let state = state()
    state.addFreeMeta("  poster ")
    state.addFreeMeta("")
    state.addFreeMeta("Poster")
    state.addFreeMeta("cinematic")
    #expect(state.document.freeMeta == ["poster", "cinematic"])
    state.removeFreeMeta(at: 0)
    #expect(state.document.freeMeta == ["cinematic"])
  }

  @Test func colorsAreLimitedToFiveEverywhere() {
    let state = state()
    state.addItem(label: .object, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5))
    for _ in 0..<8 {
      state.addColor(to: .summary)
      state.addColor(to: .item(1))
    }
    #expect(state.document.palette.count == 5 && state.document.items[0].colors.count == 5)
    #expect(state.document.palette.allSatisfy { Palette.normalize($0) == $0 })
    state.setColor("#ff0000", at: 0, in: .summary)
    #expect(state.document.palette[0] == "#FF0000")
    state.setColor("not a color", at: 1, in: .summary)
    #expect(state.document.palette[1] != "NOT A COLOR")
    state.removeColor(at: 0, from: .item(1))
    #expect(state.document.items[0].colors.count == 4)
  }

  @Test func theSendHintNamesTheFirstProblem() {
    let state = state()
    state.active = true
    #expect(state.sendHint == L.text(.problemEmptySummary, italian: false))
    state.document.description = "x"
    #expect(state.sendHint == L.text(.problemNoItems, italian: false))
    state.addItem(label: .text, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5))
    #expect(state.sendHint == L.format(.problemEmptyCaption, 1, italian: false))
    state.update(item: 1) { $0.caption = "c" }
    #expect(state.sendHint == L.format(.problemEmptyText, 1, italian: false))
    state.update(item: 1) { $0.text = "Hi" }
    #expect(state.sendHint == nil)
    state.update(generationSize: nil)
    #expect(state.sendHint == L.text(.problemUnknownSize, italian: false))
  }

  @Test func theCenteredPositionTextRoundTripsThroughTheStateHelper() {
    let state = state()
    state.addItem(label: .object, box: FracBox(x0: 0.25, y0: 0.25, x1: 0.75, y1: 0.75))
    #expect(state.positionText(of: 1) == "[-160, -256, 160, 256]")
    state.setPosition("[-320, -512, 0, 0]", of: 1)
    #expect(state.document.items[0].box == FracBox(x0: 0, y0: 0, x1: 0.5, y1: 0.5))
    state.setPosition("garbage", of: 1)  // illeggibile: il box resta
    #expect(state.document.items[0].box == FracBox(x0: 0, y0: 0, x1: 0.5, y1: 0.5))
  }

  @Test func theReasonSendIsDisabledStaysEvenAfterAStatusMessage() {
    let state = state()
    state.active = true
    state.status = "Prompt sent."
    #expect(state.statusLines == ["Prompt sent.", L.text(.problemEmptySummary, italian: false)])
    state.document.description = "x"
    state.addItem(label: .object, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5))
    state.update(item: 1) { $0.caption = "c" }
    #expect(state.statusLines == ["Prompt sent."])
    state.status = ""
    #expect(state.statusLines.isEmpty)
  }

  @Test func anItemFieldReadsTheCurrentTextEvenWhenTheCardHoldsAStaleCopy() {
    let state = state()
    state.addItem(label: .text, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5))
    let stale = state.document.items[0]  // la copia con cui la scheda è stata disegnata
    let caption = state.itemBinding(1, \.caption, fallback: stale.caption)
    caption.wrappedValue = "uno"
    state.update(item: 1) { $0.caption = "uno due" }  // un'altra battuta: la copia della scheda non è ancora stata ridisegnata
    #expect(stale.caption == "")
    #expect(caption.wrappedValue == "uno due")  // legge dal documento, non dalla copia: il cursore non salta
    caption.wrappedValue = "uno due tre"
    #expect(state.document.items[0].caption == "uno due tre")
    state.removeItem(1)  // l'elemento sparito: si ripiega sulla copia, senza errore
    #expect(state.itemBinding(1, \.tags, fallback: "x").wrappedValue == "x")
  }
}
