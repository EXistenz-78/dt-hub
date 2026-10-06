import CoreGraphics
import Foundation
import Testing

@testable import PromptMasterI4

@MainActor
@Suite("The canvas and the elements")
struct CanvasStateTests {
  private let canvas = CanvasGeometry(size: CGSize(width: 500, height: 250))

  private func state() -> I4State {
    let state = I4State(
      data: I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
      store: I4Store(storage: MemoryStorage()), italian: true)
    state.active = true
    return state
  }

  private func drag(_ mode: CanvasMode, _ start: CGPoint, _ end: CGPoint) -> CanvasDrag { CanvasDrag(mode: mode, start: start, current: end) }
  private func drawing(_ start: CGPoint, _ end: CGPoint) -> CanvasDrag { drag(.draw, start, end) }

  // MARK: Drawing

  @Test func aBoxDrawnOnEmptyCanvasIsAnObjectAndIsSelectedAndOpen() {
    let state = state()
    state.canvasEnd(drawing(CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150)), geometry: canvas)
    let element = state.document.elements[0]
    #expect(state.document.elements.count == 1 && element.type == .obj && element.bbox == BBox(y0: 200, x0: 200, y1: 600, x1: 400))
    #expect(state.selectedElement == element.id && state.expandedElements.contains(element.id))
    #expect(state.canvasItems == [CanvasItem(id: element.id, number: 1, type: .obj, box: element.bbox!)])
  }

  @Test func aBoxThatIsTooSmallMakesNothingAndDeselects() {
    let state = state()
    state.addElement(.obj)
    state.select(state.document.elements[0].id)
    state.canvasEnd(drawing(CGPoint(x: 100, y: 50), CGPoint(x: 101, y: 150)), geometry: canvas)
    #expect(state.document.elements.count == 1 && state.document.elements[0].bbox == nil && state.selectedElement == nil)
  }

  @Test func aBoxDrawnNeverGoesToAnElementThatHasNoPositionButMakesANewOne() {
    let state = state()
    state.addElement(.text)
    state.canvasEnd(drawing(CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 110)), geometry: canvas)
    #expect(state.document.elements.count == 2 && state.document.elements[0].bbox == nil && state.document.elements[1].bbox != nil)
    #expect(state.document.elements[1].type == .obj)
  }

  @Test func removingAnElementForgetsItsSelection() {
    let state = state()
    state.canvasEnd(drawing(CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150)), geometry: canvas)
    let boxed = state.document.elements[0].id
    #expect(state.selectedElement == boxed)
    state.removeElement(boxed)
    #expect(state.selectedElement == nil && state.canvasItems.isEmpty)
  }

  // MARK: Moving, resizing and selecting

  @Test func movingAndResizingSetTheBoxAndSelectTheElementAndAClickOnlySelects() {
    let state = state()
    state.canvasEnd(drawing(CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150)), geometry: canvas)
    state.addElement(.obj)
    let id = state.document.elements[0].id
    let original = state.document.elements[0].bbox!
    state.select(nil)
    state.canvasEnd(drag(.move(id: id, original: original), CGPoint(x: 150, y: 100), CGPoint(x: 200, y: 100)), geometry: canvas)
    #expect(state.document.elements[0].bbox == BBox(y0: 200, x0: 300, y1: 600, x1: 500) && state.selectedElement == id)
    state.select(nil)
    let moved = state.document.elements[0].bbox!
    state.canvasEnd(drag(.move(id: id, original: moved), CGPoint(x: 200, y: 100), CGPoint(x: 201, y: 100)), geometry: canvas)
    #expect(state.document.elements[0].bbox == moved && state.selectedElement == id)  // a click
    state.canvasEnd(drag(.resize(id: id, corner: .se, original: moved), CGPoint(x: 250, y: 150), CGPoint(x: 300, y: 200)), geometry: canvas)
    #expect(state.document.elements[0].bbox == BBox(y0: 200, x0: 300, y1: 800, x1: 600))
  }

  // MARK: The tag

  @Test func aClickOnTheTagOfAnUnselectedBoxSelectsItAndOnASelectedBoxChangesItsType() {
    let state = state()
    state.canvasEnd(drawing(CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150)), geometry: canvas)
    let id = state.document.elements[0].id
    state.select(nil)
    let click = drag(.tag(id: id), CGPoint(x: 60, y: 40), CGPoint(x: 60, y: 40))
    state.canvasEnd(click, geometry: canvas)
    #expect(state.selectedElement == id && state.document.elements[0].type == .obj)  // selected only
    state.canvasEnd(click, geometry: canvas)
    #expect(state.document.elements[0].type == .text)
    state.canvasEnd(click, geometry: canvas)
    #expect(state.document.elements[0].type == .obj)  // and back
    #expect(state.canvasItems[0].label == "E1 · obj")
  }

  @Test func draggingFromATagDoesNothing() {
    let state = state()
    state.canvasEnd(drawing(CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150)), geometry: canvas)
    let id = state.document.elements[0].id
    state.select(id)
    state.canvasEnd(drag(.tag(id: id), CGPoint(x: 60, y: 40), CGPoint(x: 300, y: 200)), geometry: canvas)
    #expect(state.document.elements[0].type == .obj && state.document.elements[0].bbox == BBox(y0: 200, x0: 200, y1: 600, x1: 400))
  }

  @Test func changingTheTypeKeepsTheDescriptionTheLetteringAndTheText() {
    var document = I4Document()
    let id = document.addElement(type: .text)
    document.updateElement(id) {
      $0.desc = "above the door"
      $0.lettering = "ty_neon_sign"
      $0.text = "BAR"
    }
    document.toggleType(id)
    document.toggleType(id)
    #expect(document.elements[0].type == .text && document.elements[0].lettering == "ty_neon_sign" && document.elements[0].text == "BAR")
    document.toggleType(999)  // an element that is gone: nothing
  }

  // MARK: The shape of the canvas

  @Test func theCanvasTakesTheProportionsOfTheGenerationAndIsSquareUntilTheAppHasSaid() {
    let state = state()
    #expect(state.canvasAspect == 1 && state.generationSize == nil)
    state.update(generationSize: CGSize(width: 1280, height: 832))
    #expect(abs(state.canvasAspect - 1280.0 / 832.0) < 1e-9)
    state.update(generationSize: CGSize(width: 0, height: 832))
    #expect(state.canvasAspect == 1)
    state.update(generationSize: nil)
    #expect(state.canvasAspect == 1)
  }

  @Test func theSelectionIsNotRememberedAcrossRuns() {
    let storage = MemoryStorage()
    let data = I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: [])
    let first = I4State(data: data, store: I4Store(storage: storage), italian: true)
    first.addElement(.obj)
    first.select(first.document.elements[0].id)
    let again = I4State(data: data, store: I4Store(storage: storage), italian: true)
    #expect(again.document.elements.count == 1 && again.selectedElement == nil)
  }
}
