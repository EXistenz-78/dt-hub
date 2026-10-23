import CoreGraphics
import Foundation
import Testing

@testable import PromptMasterMOSS

struct CanvasGeometryTests {
  /// Una tela di 400×250 punti per una Generazione 1024×640.
  let geometry = CanvasGeometry(size: CGSize(width: 400, height: 250), pixels: PixelSize(width: 1024, height: 640))
  let panel = CanvasItem(id: 1, number: 1, label: .panel, box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1))
  let cup = CanvasItem(id: 2, number: 2, label: .object, box: FracBox(x0: 0.4, y0: 0.4, x1: 0.6, y1: 0.7))

  func drag(_ mode: CanvasMode, from a: CGPoint, to b: CGPoint) -> CanvasDrag { CanvasDrag(mode: mode, start: a, current: b) }

  @Test func theTagOfAnItemSaysNumberAndLabel() {
    #expect(cup.tag == "E2 · object")
    #expect(CanvasItem(id: 9, number: 3, label: .subject, box: cup.box).tag == "E3 · subject")
  }

  @Test func pointsAndFractionsAreKeptInsideTheCanvas() {
    #expect(geometry.fraction(CGPoint(x: 200, y: 125)) == (0.5, 0.5))
    #expect(geometry.fraction(CGPoint(x: -50, y: 900)) == (0, 1))
  }

  @Test func aPressOnEmptySpaceDraws_onAnUnselectedBoxMoves_onTheSelectedCornerResizes() {
    #expect(geometry.begin(at: CGPoint(x: 390, y: 240), items: [cup], selected: nil) == .draw)
    #expect(geometry.begin(at: CGPoint(x: 200, y: 150), items: [cup], selected: nil) == .move(id: 2, original: cup.box))
    let corner = geometry.handlePoint(.se, of: geometry.rect(of: cup.box))
    #expect(geometry.begin(at: corner, items: [cup], selected: 2) == .resize(id: 2, corner: .se, original: cup.box))
  }

  @Test func aPressOnATagIsATagPress() {
    let tag = geometry.tagRect(for: cup)
    #expect(geometry.begin(at: CGPoint(x: tag.midX, y: tag.midY), items: [panel, cup], selected: nil) == .tag(id: 2))
  }

  @Test func drawingMakesABoxInFractions_aTinyOneIsNothing() {
    let drawn = geometry.result(of: drag(.draw, from: CGPoint(x: 40, y: 25), to: CGPoint(x: 240, y: 175)))
    #expect(drawn == FracBox(x0: 0.1, y0: 0.1, x1: 0.6, y1: 0.7))
    #expect(geometry.result(of: drag(.draw, from: CGPoint(x: 40, y: 25), to: CGPoint(x: 41, y: 26))) == nil)
  }

  @Test func movingKeepsTheSizeAndStaysInsideTheCanvas() {
    let moved = geometry.result(of: drag(.move(id: 2, original: cup.box), from: CGPoint(x: 200, y: 125), to: CGPoint(x: 900, y: -500)))
    #expect(moved != nil)
    #expect(abs((moved!.x1 - moved!.x0) - 0.2) < 1e-9 && abs((moved!.y1 - moved!.y0) - 0.3) < 1e-9)
    #expect(moved!.x1 == 1 && moved!.y0 == 0)
  }

  @Test func resizingKeepsTheOppositeCornerAndTheMinimumSide() {
    let mode = CanvasMode.resize(id: 2, corner: .se, original: cup.box)
    let shrunk = geometry.result(of: drag(mode, from: CGPoint(x: 240, y: 175), to: CGPoint(x: 100, y: 100)))
    #expect(shrunk?.x0 == 0.4 && shrunk?.y0 == 0.4)
    // 2 % del lato corto (640 px): 0,0125 della larghezza e 0,02 dell'altezza
    #expect(abs(shrunk!.x1 - 0.4 - 0.0125) < 1e-9 && abs(shrunk!.y1 - 0.4 - 0.02) < 1e-9)
  }

  @Test func theMinimumSideFollowsTheShapeOfTheGeneration() {
    let wide = CanvasGeometry(size: CGSize(width: 300, height: 200), pixels: PixelSize(width: 1536, height: 1024))
    let box = FracBox(x0: 0.2, y0: 0.2, x1: 0.5, y1: 0.5)
    let shrunk = wide.result(of: drag(.resize(id: 1, corner: .se, original: box), from: CGPoint(x: 150, y: 100), to: CGPoint(x: 0, y: 0)))
    #expect(abs(shrunk!.x1 - 0.2 - 0.02 * 1024 / 1536) < 1e-9 && abs(shrunk!.y1 - 0.2 - 0.02) < 1e-9)
  }

  @Test func theCanvasFitsTheShapeOfTheGeneration() {
    #expect(CanvasGeometry.fit(aspect: 2, in: CGSize(width: 400, height: 400)) == CGSize(width: 400, height: 200))
    #expect(CanvasGeometry.fit(aspect: 0.5, in: CGSize(width: 400, height: 200)) == CGSize(width: 100, height: 200))
    #expect(CanvasGeometry.fit(aspect: .nan, in: CGSize(width: 100, height: 100)) == CGSize(width: 100, height: 100))
  }

  @Test func theGenerationSizeComesFromTheContextMessage() {
    let message = Data(#"{"type":"context","parameters":{"width":1024,"height":640}}"#.utf8)
    #expect(GenerationSize.read(fromContext: message) == PixelSize(width: 1024, height: 640))
    #expect(GenerationSize.read(fromContext: Data(#"{"type":"context"}"#.utf8)) == nil)
  }
}

@MainActor
struct CanvasStateTests {
  func state() -> MossState {
    let state = MossState(
      data: MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub")),
      promptFolder: MossPrompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-canvas-\(UUID().uuidString)")),
      store: MossStore(storage: MemoryStorage()), italian: false, shuffler: { _, _ in [] })
    state.update(generationSize: PixelSize(width: 1024, height: 640))
    return state
  }
  let geometry = CanvasGeometry(size: CGSize(width: 400, height: 250), pixels: PixelSize(width: 1024, height: 640))

  @Test func theCanvasItemsAreNumberedByPosition() {
    let state = state()
    state.addItem(label: .panel, box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1))
    state.addItem(label: .text, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.3, y1: 0.2))
    #expect(state.canvasItems.map(\.number) == [1, 2])
    #expect(state.canvasItems.map(\.label) == [.panel, .text])
  }

  @Test func aFinishedDrawingAddsAnObjectAndSelectsIt_aClickOnEmptySpaceDeselects() {
    let state = state()
    state.canvasEnd(CanvasDrag(mode: .draw, start: CGPoint(x: 40, y: 25), current: CGPoint(x: 240, y: 175)), geometry: geometry)
    #expect(state.document.items.count == 1 && state.document.items[0].label == .object)
    #expect(state.selectedItem == state.document.items[0].id)
    state.canvasEnd(CanvasDrag(mode: .draw, start: CGPoint(x: 5, y: 5), current: CGPoint(x: 5, y: 5)), geometry: geometry)
    #expect(state.document.items.count == 1 && state.selectedItem == nil)
  }

  @Test func clickingATagSelectsTheBoxAndOpensTheTypeMenu_choosingATypeClosesIt() {
    let state = state()
    state.addItem(label: .object, box: FracBox(x0: 0.4, y0: 0.4, x1: 0.6, y1: 0.7))
    state.selectedItem = nil
    state.canvasEnd(CanvasDrag(mode: .tag(id: 1), start: .zero, current: .zero), geometry: geometry)
    #expect(state.selectedItem == 1 && state.typeMenuItem == 1)
    state.chooseLabel(.subject, for: 1)
    #expect(state.document.items[0].label == .subject && state.typeMenuItem == nil)
  }

  @Test func movingOrResizingUpdatesTheBoxAndClosesTheMenu() {
    let state = state()
    state.addItem(label: .object, box: FracBox(x0: 0.4, y0: 0.4, x1: 0.6, y1: 0.7))
    state.typeMenuItem = 1
    let original = state.document.items[0].box
    state.canvasEnd(
      CanvasDrag(mode: .move(id: 1, original: original), start: CGPoint(x: 200, y: 125), current: CGPoint(x: 240, y: 125)), geometry: geometry)
    #expect(state.typeMenuItem == nil)
    #expect(abs(state.document.items[0].box.x0 - 0.5) < 1e-9)
  }
}
