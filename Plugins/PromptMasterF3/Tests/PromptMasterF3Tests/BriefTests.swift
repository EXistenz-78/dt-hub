import Testing

@testable import PromptMasterF3

struct BriefTests {
  let catalog = F3Catalog(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig)

  func element(_ id: String, _ desc: String) -> F3Element {
    F3Element(id: id, desc: desc, box: BBox(y0: 0, x0: 0, y1: 100, x1: 100), colorIndex: 0, expanded: false)
  }

  @Test func messageHasMarkdownBlocksAndTheShape() {
    var document = F3Document()
    document.description = "due amici in una tavola calda"
    document.composition = "Ci sono una donna <woman_1>."
    document.elements = [element("woman_1", "una giovane donna")]
    let parts = F3Brief.parts(from: document, catalog: catalog)
    let message = F3Brief.message(parts)
    let expected = """
      ## description
      due amici in una tavola calda

      ## composition
      Ci sono una donna <woman_1>.

      ## element: woman_1
      una giovane donna

      Reply in English, in exactly this shape, replacing the dots with the English text:
      ## description
      ...

      ## composition
      ...

      ## element: woman_1
      ...
      """
    #expect(message == expected)
  }

  @Test func termsAreCategoryLinesInEnglishAndSkipEmptyDescription() throws {
    var document = F3Document()
    let light = try #require(catalog.categories(mode: .photo).first { $0.id == "light_source" })
    document.choose(light.terms[0].id, catalog: catalog)
    let parts = F3Brief.parts(from: document, catalog: catalog)
    #expect(parts.count == 1)
    #expect(parts[0].kind == .description)
    #expect(parts[0].terms == ["\(light.en): \(light.terms[0].en)"])
    #expect(F3Brief.message(parts).contains("## description\n\(light.en): \(light.terms[0].en)"))
  }

  @Test func emptyPartsAreNotRequested() {
    var document = F3Document()
    document.composition = "  "
    document.elements = [element("a", " ")]
    #expect(F3Brief.parts(from: document, catalog: catalog).isEmpty)
  }

  @Test func positionsAndColorsAreNeverSent() {
    var document = F3Document()
    document.composition = "<a>"
    document.elements = [element("a", "x")]
    let message = F3Brief.message(F3Brief.parts(from: document, catalog: catalog))
    #expect(!message.contains("bbox") && !message.contains("100"))
  }

  @Test func reminderComesBeforeTheShape() {
    let message = F3Brief.message([F3Part(kind: .composition, text: "<a>")], reminder: "KEEP")
    #expect(message.contains("<a>\n\nKEEP\n\nReply in English, in exactly"))
  }
}
