import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The request to the language model")
struct BriefTests {
  private let catalog = I4Catalog(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig)

  @Test func theRequestHasABlockForEachFieldWithItsTagAndTheContextAtTheEnd() {
    var document = I4Document()
    document.description = "due amici"
    document.choose("ls_neon", catalog: catalog)
    let object = document.addElement(type: .obj)
    let text = document.addElement(type: .text)
    document.updateElement(object) { $0.desc = "una tazza" }
    document.updateElement(text) {
      $0.desc = "sopra la porta"
      $0.text = "BAR"
    }
    let fields = document.fields(catalog: catalog)
    let targets = fields.filter(\.needsWriting)
    let request = I4Brief.make(targets: targets, written: [(tag: "medium", text: "On film.")])
    #expect(
      request == """
        <high_level_description>
        due amici
        </high_level_description>
        <lighting>
        Light Source: Neon lighting
        </lighting>
        <element_1 kind="object">
        una tazza
        </element_1>
        <element_2 kind="text">
        Lettering style notes: sopra la porta
        </element_2>
        <already_written>
        medium: On film.
        </already_written>
        Reply in exactly this shape, replacing the dots with the sentence:
        <high_level_description>...</high_level_description>
        <lighting>...</lighting>
        <element_1>...</element_1>
        <element_2>...</element_2>
        """)
  }

  @Test func theRequestNeverCarriesPositionsOrColors() {
    var document = I4Document()
    document.addColor("#123456")
    let id = document.addElement(type: .obj, bbox: BBox(y0: 11, x0: 22, y1: 333, x1: 444))
    document.updateElement(id) {
      $0.desc = "una tazza"
      $0.colors = ["#ABCDEF"]
    }
    let request = I4Brief.make(targets: document.fieldsToWrite(catalog: catalog))
    for forbidden in ["11", "333", "444", "#123456", "#ABCDEF", "bbox"] { #expect(!request.contains(forbidden), "\(forbidden)") }
  }

  @Test func theContextIsTheFinalSentencesOfTheFieldsThatAreNotAsked() {
    var document = I4Document()
    document.description = "una scena"
    document.choose("ls_neon", catalog: catalog)
    let all = document.fields(catalog: catalog)
    document.written["lighting"] = WrittenPhrase(text: "Lit by neon.", input: all.first { $0.id == "lighting" }!.input)
    let fields = document.fields(catalog: catalog)
    let targets = fields.filter(\.needsWriting)
    #expect(targets.map(\.id) == ["description"])
    let context = I4Brief.context(of: fields, excluding: targets)
    #expect(context.count == 1 && context[0].tag == "lighting" && context[0].text == "Lit by neon.")
    #expect(I4Brief.context(of: fields, excluding: [fields.first { $0.id == "lighting" }!]).isEmpty)
    #expect(!I4Brief.make(targets: targets).contains("already_written"))
  }
}
