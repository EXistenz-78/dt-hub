import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterMing

@MainActor
@Suite("The tab's state")
struct StateTests {
  @Test func importingFromTheGenerationFillsTheCardsAndAsksForTheShape() throws {
    let state = Fixture.state(size: PixelSize(width: 1024, height: 1024))
    state.document.imageStyle = "old"
    state.addLayer(kind: .object, box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1))
    #expect(!state.importOffer)
    state.update(generationPrompt: Fixture.familyStyle)
    #expect(state.importOffer)
    let size = try state.importFromGeneration().get()
    #expect(size == PixelSize(width: 1248, height: 832))
    #expect(state.document.layers.count == 3 && state.document.layers.map(\.id) == [1, 2, 3] && state.document.nextLayerID == 4)
    #expect(state.document.imageStyle == "flat vector poster" && state.document.ambientLighting == "bright daylight")
    #expect(state.document.layers[1].kind == .text && state.document.layers[1].text == "SUMMER SALE")
    #expect(!state.importOffer)  // handled
    state.undo()
    #expect(state.document.imageStyle == "old" && state.document.layers.count == 1)
  }

  @Test func aJSONOfTheSameShapeKeepsTheSizeAndAnInvalidOneChangesNothing() throws {
    let state = Fixture.state()
    state.update(generationPrompt: Fixture.golden)
    #expect(try state.importFromGeneration().get() == nil)
    #expect(state.currentJSON() == Fixture.golden)
    #expect(!state.importOffer)  // the tab would send the same JSON
    state.update(generationPrompt: "a cat")
    let before = state.document
    #expect((try? state.importFromGeneration().get()) == nil)
    #expect(state.document == before && state.status.contains("Not a Ming JSON"))
  }

  @Test func theOfferCanBeDismissedForThatPrompt() {
    let state = Fixture.state()
    state.update(generationPrompt: Fixture.familyStyle)
    #expect(state.importOffer)
    state.dismissImportOffer()
    #expect(!state.importOffer)
  }

  @Test func sendNeedsDescriptionsAndWords() {
    let state = Fixture.state()
    #expect(state.problems == [.noLayers] && !state.canSend)
    state.addLayer(kind: .text, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.3))
    #expect(state.problems == [.emptyText(layer: 1)])
    state.update(layer: 1) { $0.text = "HELLO" }
    #expect(state.canSend)
    state.addLayer(kind: .object, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.3))
    #expect(state.problems == [.emptyDescription(layer: 2)])
  }

  @Test func termsGoToStyleAndLight() {
    let state = Fixture.state()
    let light = state.catalog.categories(mode: .art).first { $0.id == "light_scheme" }!.terms[0]
    state.choose(light.id)
    state.document.ambientLighting = "warm."
    state.document.imageStyle = "poster"
    state.update(layer: 0) { _ in }
    state.addLayer(kind: .object, box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1))
    state.update(layer: 1) { $0.description = "bg" }
    let json = state.currentJSON() ?? ""
    #expect(json.contains("\"ambient_lighting\": \"warm, \(light.en)\""))
    #expect(json.contains("\"image_style\": \"poster\""))
  }

  @Test func theSessionIsKeptPerProject() {
    let storage = MemoryStorage()
    let state = Fixture.state(storage: storage)
    state.document.idea = "remember me"
    let again = Fixture.state(storage: storage)
    #expect(again.document.idea == "remember me")
  }

  @Test func clearAllCanBeUndone() {
    let state = Fixture.state()
    state.addLayer(kind: .object, box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1))
    state.clearAll()
    #expect(state.document.layers.isEmpty && state.canUndo)
    state.undo()
    #expect(state.document.layers.count == 1)
  }
}

@MainActor
@Suite("Writing and composing with a stand-in language model")
struct WriterTests {
  @Test func theTextsAreRewrittenInEnglishAndTheExactWordsAreNeverSent() async {
    let state = Fixture.state()
    state.document.imageStyle = "poster minimale"
    state.addLayer(kind: .text, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.9, y1: 0.2))
    state.update(layer: 1) {
      $0.text = "SEGRETO"
      $0.description = "lettere bianche"
      $0.relation = "sopra il prodotto"
    }
    var asked = ""
    let writer = MingWriter(ask: { prompt, _, _ in
      asked = prompt
      return .text("## image_style\nMinimal poster.\n\n## layer 1 (text)\nBold white sans-serif letters.\n\n## relation 1\nAbove the product.")
    }, italian: false)
    let result = await writer.write(document: state.document, catalog: state.catalog, system: "s", options: DTHubLLMOptions())
    #expect(!asked.contains("SEGRETO"))
    state.apply(result)
    #expect(state.document.imageStyle == "Minimal poster.")
    #expect(state.document.layers[0].description == "Bold white sans-serif letters." && state.document.layers[0].relation == "Above the product.")
    #expect(state.document.layers[0].text == "SEGRETO" && state.canUndo)
  }

  @Test func composeReadsTheJSONAndRetriesOnce() async throws {
    let state = Fixture.state()
    state.document.idea = "un poster"
    let request = try #require(state.composeRequest())
    #expect(request.contains("\"aspect_ratio\": \"2:3\"") && request.contains("un poster"))
    var calls = 0
    let writer = MingWriter(ask: { _, _, _ in
      calls += 1
      return .text(calls == 1 ? "Sorry, here is a layout" : "<think>hm</think>" + Fixture.golden)
    }, italian: false)
    let result = await writer.compose(request: request, system: "s", options: DTHubLLMOptions())
    #expect(calls == 2)
    let imported = try #require(result.imported)
    state.apply(imported: imported, source: "LLM")
    #expect(state.document.layers.count == 2 && state.currentJSON() == Fixture.golden)
  }
}
