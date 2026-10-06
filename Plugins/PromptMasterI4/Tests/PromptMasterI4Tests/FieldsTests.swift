import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The fields the language model writes")
struct FieldsTests {
  private let catalog = I4Catalog(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig)

  private func field(_ document: I4Document, _ id: String) -> I4FieldInfo {
    document.fields(catalog: catalog).first { $0.id == id }!
  }

  // MARK: What is sent

  @Test func theFieldsAreInTheOrderOfTheCaptionAndEmptyOnesAreEmpty() {
    let document = I4Document()
    let fields = document.fields(catalog: catalog)
    #expect(fields.map(\.tag) == ["high_level_description", "aesthetics", "lighting", "photo", "medium", "background"])
    #expect(fields.allSatisfy { $0.state == .empty && $0.input.isEmpty && !$0.needsWriting })
    var art = document
    art.mode = .art
    #expect(art.fields(catalog: catalog).map(\.tag).contains("art_style") && !art.fields(catalog: catalog).map(\.tag).contains("photo"))
  }

  @Test func theTermsAreLinesWithTheirCategoryInEnglishInTheOrderOfTheCategories() {
    var document = I4Document()
    document.description = "  due amici in una tavola calda  "
    for id in ["lq_soft", "ls_neon", "mo_peaceful", "ch_analogous", "fr_medium", "fs_film_grain"] { document.choose(id, catalog: catalog) }
    #expect(field(document, "description").lines == ["due amici in una tavola calda"])
    #expect(field(document, "aesthetics").lines == ["Mood: peaceful", "Color Harmony: Analogous colors"])
    #expect(field(document, "lighting").lines == ["Light Source: Neon lighting", "Light Quality & Shadow: Soft light"])
    #expect(field(document, "style").lines == ["Framing: Medium shot"])
    #expect(field(document, "medium").lines == ["Film Stock & Process: Film grain"])
    #expect(field(document, "lighting").block == "Light Source: Neon lighting\nLight Quality & Shadow: Soft light")
  }

  @Test func theBackgroundIsTheUsersWordsThenTheChosenBackdrop() {
    var document = I4Document()
    document.background = "la strada bagnata"
    document.choose("bg_blurred", catalog: catalog)
    #expect(field(document, "background").lines == ["la strada bagnata", "Background Setup: blurred background"])
    #expect(field(document, "background").raw == "la strada bagnata, blurred background")
  }

  @Test func anObjectIsItsDescriptionAndATextIsItsNotesItsLetteringTermAndNeverTheWordsItPrints() {
    var document = I4Document()
    let object = document.addElement(type: .obj)
    let text = document.addElement(type: .text)
    let empty = document.addElement(type: .obj)
    let wordsOnly = document.addElement(type: .text)
    document.updateElement(object) { $0.desc = "un cliente solo" }
    document.updateElement(text) {
      $0.desc = "sopra la finestra"
      $0.lettering = "ty_neon_sign"
      $0.text = "OPEN ALL NIGHT"
    }
    document.updateElement(wordsOnly) { $0.text = "HELLO" }
    let o = field(document, I4FieldInfo.elementID(object)), t = field(document, I4FieldInfo.elementID(text))
    #expect(o.tag == "element_1" && o.kind == "object" && o.lines == ["un cliente solo"] && o.title == "E1 · obj")
    #expect(t.tag == "element_2" && t.kind == "text" && t.title == "E2 · text")
    #expect(t.lines == ["Lettering style notes: sopra la finestra", "Text & Lettering: neon sign lettering"])
    #expect(!t.block.contains("OPEN ALL NIGHT") && !t.lines.joined().contains("OPEN"))  // the words it prints never go to the model
    #expect(field(document, I4FieldInfo.elementID(empty)).state == .empty)
    #expect(field(document, I4FieldInfo.elementID(wordsOnly)).state == .empty)
    // And changing them never makes its sentence stale.
    var other = document
    other.updateElement(text) { $0.text = "CLOSED" }
    #expect(field(other, I4FieldInfo.elementID(text)).input == t.input)
  }

  // MARK: States

  @Test func aFieldIsRawThenWrittenThenStaleWhenItsInputChangesAndEmptyWhenItEmpties() {
    var document = I4Document()
    document.description = "una scena"
    #expect(field(document, "description").state == .raw && field(document, "description").needsWriting)
    let first = field(document, "description")
    document.written["description"] = WrittenPhrase(text: "A scene.", input: first.input)
    #expect(field(document, "description").state == .written && !field(document, "description").needsWriting)
    #expect(field(document, "description").value == "A scene." && field(document, "description").raw == "una scena")
    document.description = "un'altra scena"
    #expect(field(document, "description").state == .stale && field(document, "description").value == "un'altra scena")
    document.description = ""
    #expect(field(document, "description").state == .empty)
    document.pruneWritten(catalog: catalog)
    #expect(document.written.isEmpty)
  }

  @Test func changingTheTypeOfAnElementOrTheModeMakesItsSentenceStale() {
    var document = I4Document()
    let id = document.addElement(type: .obj, bbox: BBox(y0: 0, x0: 0, y1: 100, x1: 100))
    document.updateElement(id) { $0.desc = "a cup" }
    let key = I4FieldInfo.elementID(id)
    document.written[key] = WrittenPhrase(text: "A cup.", input: field(document, key).input)
    #expect(field(document, key).state == .written)
    document.toggleType(id)
    #expect(field(document, key).state == .stale)
    document.choose("fr_closeup", catalog: catalog)
    document.written["style"] = WrittenPhrase(text: "Close-up.", input: field(document, "style").input)
    #expect(field(document, "style").state == .written)
    document.setMode(.art, catalog: catalog)
    #expect(field(document, "style").state == .empty && field(document, "style").tag == "art_style")
  }

  @Test func theCaptionUsesTheSentenceOnlyWhileItIsCurrentAndRemovingAnElementPrunesIt() {
    var document = I4Document()
    document.description = "una scena"
    document.choose("ls_neon", catalog: catalog)
    let id = document.addElement(type: .obj)
    document.updateElement(id) { $0.desc = "una tazza" }
    for key in ["description", "lighting", I4FieldInfo.elementID(id)] {
      document.written[key] = WrittenPhrase(text: "WRITTEN \(key)", input: field(document, key).input)
    }
    var caption = document.caption(catalog: catalog)
    #expect(caption.description == "WRITTEN description" && caption.lighting == "WRITTEN lighting" && caption.elements[0].desc == "WRITTEN element:\(id)")
    document.description = "cambiata"
    caption = document.caption(catalog: catalog)
    #expect(caption.description == "cambiata" && caption.lighting == "WRITTEN lighting")
    document.removeElement(id)
    document.pruneWritten(catalog: catalog)
    #expect(Set(document.written.keys) == ["description", "lighting"])  // a stale sentence is kept; a removed element's goes
  }

  @Test func aSessionSavedBeforeTheLanguageModelHasNoWrittenSentencesAndStillReads() throws {
    let document = I4Document()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    object.removeValue(forKey: "written")
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(I4Document.self, from: old).written.isEmpty)
    var withPhrase = document
    withPhrase.written["lighting"] = WrittenPhrase(text: "x", input: "y")
    #expect(try JSONDecoder().decode(I4Document.self, from: JSONEncoder().encode(withPhrase)) == withPhrase)
  }
}
