import Foundation
import Testing

@testable import PromptMasterMOSS

struct BriefTests {
  let data = MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))
  var catalog: MossCatalog { MossCatalog(database: data.database, config: data.config) }

  func item(_ id: Int, _ label: MossLabel, caption: String, text: String = "", tags: String = "", colors: [String] = []) -> MossItem {
    MossItem(id: id, label: label, caption: caption, text: text, tags: tags, colors: colors, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.6, y1: 0.6), expanded: false)
  }

  /// La prima voce di `light_source` e il nome inglese della sua categoria, come li scrive il messaggio.
  var lightLine: (id: String, line: String) {
    let category = data.database.categories.first { $0.id == "light_source" }!
    return (category.terms[0].id, "\(category.en): \(category.terms[0].en)")
  }

  @Test func messageMatchesTheExampleOfTheSpec() {
    var document = MossDocument()
    document.description = "due amici in una foresta di bambù, di notte"
    document.selection = [lightLine.id]
    document.items = [item(1, .panel, caption: "sfondo di bambù"), item(2, .text, caption: "scritta bianca in basso a sinistra", text: "Kyoto")]
    let message = MossBrief.message(MossBrief.parts(from: document, catalog: catalog))
    let expected = """
      ## summary
      due amici in una foresta di bambù, di notte
      \(lightLine.line)

      ## element 1 (panel)
      sfondo di bambù

      ## element 2 (text)
      scritta bianca in basso a sinistra

      Reply in English, in exactly this shape, replacing the dots with the English text:
      ## summary
      ...

      ## element 1 (panel)
      ...

      ## element 2 (text)
      ...
      """
    #expect(message == expected)
  }

  @Test func metaTermsOfTheDatabaseAreNotSent_freeMetaIs() {
    var document = MossDocument()
    document.description = "x"
    document.selection = [data.database.categories.first { $0.id == "photo_genre" }!.terms[0].id]
    #expect(!MossBrief.parts(from: document, catalog: catalog).contains { $0.kind == .meta })
    #expect(!MossBrief.message(MossBrief.parts(from: document, catalog: catalog)).contains("Photo"))
    document.freeMeta = ["foresta", "notte"]
    let meta = MossBrief.parts(from: document, catalog: catalog).first { $0.kind == .meta }
    #expect(meta?.text == "foresta, notte")
  }

  @Test func tagsPartsOnlyForItemsThatHaveTags() {
    var document = MossDocument()
    document.items = [item(1, .object, caption: "a", tags: "tazza, ceramica"), item(2, .object, caption: "b")]
    let kinds = MossBrief.parts(from: document, catalog: catalog).map(\.kind)
    #expect(kinds == [.item(id: 1, label: .object), .tags(id: 1), .item(id: 2, label: .object)])
  }

  @Test func neverTheTextNorTheColorsNorThePositions() {
    var document = MossDocument()
    document.items = [item(1, .text, caption: "white lettering", text: "SECRET-TEXT-123", colors: ["#ABCDEF"])]
    let message = MossBrief.message(MossBrief.parts(from: document, catalog: catalog))
    #expect(!message.contains("SECRET") && !message.contains("ABCDEF") && !message.contains("bbox") && !message.contains("0.1"))
  }

  @Test func emptyPartsAreNotRequested() {
    var document = MossDocument()
    document.items = [item(1, .object, caption: "  "), item(2, .object, caption: "ok")]
    #expect(MossBrief.parts(from: document, catalog: catalog).map(\.kind) == [.item(id: 2, label: .object)])
    #expect(MossBrief.parts(from: MossDocument(), catalog: catalog).isEmpty)
  }

  @Test func aReminderGoesBeforeTheShape() {
    var document = MossDocument()
    document.description = "x"
    let message = MossBrief.message(MossBrief.parts(from: document, catalog: catalog), reminder: "Answer in English only.")
    let reminder = message.range(of: "Answer in English only.")!.lowerBound
    let shape = message.range(of: "Reply in English")!.lowerBound
    #expect(reminder < shape)
  }
}
