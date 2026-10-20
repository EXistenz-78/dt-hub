import Foundation
import Testing

@testable import PromptMasterF3

struct DocumentTests {
  let catalog = F3Catalog(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig)

  func terms(_ id: String, mode: StyleMode = .photo) -> [PMTerm] { catalog.categories(mode: mode).first { $0.id == id }!.terms }

  @Test func chooseKeepsOneTermPerCategory() {
    var document = F3Document()
    let light = terms("light_source")
    document.choose(light[0].id, catalog: catalog)
    document.choose(light[1].id, catalog: catalog)
    #expect(document.selection == [light[1].id])
  }

  @Test func chooseTwiceRemoves() {
    var document = F3Document()
    let id = terms("light_source")[0].id
    document.choose(id, catalog: catalog)
    document.choose(id, catalog: catalog)
    #expect(document.selection.isEmpty)
  }

  @Test func chooseIgnoresHiddenCategories() {
    var document = F3Document()
    document.choose(terms("art_movement", mode: .art)[0].id, catalog: catalog)
    #expect(document.selection.isEmpty)
  }

  @Test func switchingToArtDropsPhotoOnlyChoices() {
    var document = F3Document()
    document.choose(terms("framing")[0].id, catalog: catalog)
    document.choose(terms("light_source")[0].id, catalog: catalog)
    document.setMode(.art, catalog: catalog)
    #expect(document.selection == [terms("light_source")[0].id])
  }

  @Test func moveElementSwaps() {
    var document = F3Document()
    let box = BBox(y0: 0, x0: 0, y1: 100, x1: 100)
    document.elements = ["a", "b", "c"].map { F3Element(id: $0, desc: "", box: box, colorIndex: 0, expanded: false) }
    document.moveElement("a", by: 1)
    #expect(document.elements.map(\.id) == ["b", "a", "c"])
    document.moveElement("c", by: 1)
    #expect(document.elements.map(\.id) == ["b", "a", "c"])
  }

  @Test func roundTripsThroughJSON() throws {
    var document = F3Document()
    document.description = "x"
    document.snapshot = F3Snapshot(description: "o", selection: ["t"], composition: "c <a>", descs: ["a": "d"])
    let data = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(F3Document.self, from: data) == document)
  }
}
