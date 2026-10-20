import CoreGraphics
import Foundation
import Testing

@testable import PromptMasterF3

struct CanvasGeometryTests {
  /// Un canvas di 500 × 250 punti: 1 punto di larghezza vale 2 unità di griglia, 1 punto di altezza ne vale 4.
  private let canvas = CanvasGeometry(size: CGSize(width: 500, height: 250))

  private func item(_ id: String, _ box: BBox) -> CanvasItem { CanvasItem(id: id, colorIndex: 0, box: box) }

  private func drag(_ mode: CanvasMode, _ start: CGPoint, _ end: CGPoint) -> CanvasDrag { CanvasDrag(mode: mode, start: start, current: end) }

  @Test func pointsBecomeGridUnitsAndStayInside() {
    let middle = canvas.grid(CGPoint(x: 250, y: 125))
    #expect(middle.x == 500 && middle.y == 500)
    let outside = canvas.grid(CGPoint(x: -30, y: 900))
    #expect(outside.x == 0 && outside.y == 1000)
  }

  @Test func pressOnEmptyDoesNothing() {
    let items = [item("a", BBox(y0: 200, x0: 100, y1: 600, x1: 500))]
    #expect(canvas.begin(at: CGPoint(x: 400, y: 200), items: items, selected: nil) == .none)
    #expect(CanvasGeometry(size: .zero).begin(at: .zero, items: items, selected: nil) == .none)
  }

  @Test func draggingOnEmptyMakesNoBox() {
    let gesture = drag(.none, CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 100))
    #expect(canvas.preview(of: gesture) == nil)
    #expect(canvas.result(of: gesture) == nil)
  }

  @Test func pressInsideABoxMovesIt() {
    let box = BBox(y0: 200, x0: 100, y1: 600, x1: 500)
    let mode = canvas.begin(at: CGPoint(x: 100, y: 75), items: [item("a", box)], selected: nil)
    #expect(mode == .move(id: "a", original: box))
  }

  @Test func movingStaysInsideTheGridAndKeepsTheSize() {
    let box = BBox(y0: 200, x0: 100, y1: 600, x1: 500)
    let result = canvas.result(of: drag(.move(id: "a", original: box), CGPoint(x: 100, y: 75), CGPoint(x: 5000, y: 5000)))
    #expect(result == BBox(y0: 600, x0: 600, y1: 1000, x1: 1000))
  }

  @Test func theCornersOfTheSelectedBoxResize() {
    let box = BBox(y0: 200, x0: 100, y1: 600, x1: 500)
    let items = [item("a", box)]
    let handle = canvas.handlePoint(.se, of: canvas.rect(of: box))
    let mode = canvas.begin(at: handle, items: items, selected: "a")
    #expect(mode == .resize(id: "a", corner: .se, original: box))
    let result = canvas.result(of: drag(mode, handle, CGPoint(x: handle.x + 50, y: handle.y + 25)))
    #expect(result == BBox(y0: 200, x0: 100, y1: 700, x1: 600))
  }

  @Test func resizingKeepsTheMinimumSide() {
    let box = BBox(y0: 200, x0: 100, y1: 600, x1: 500)
    let handle = canvas.handlePoint(.se, of: canvas.rect(of: box))
    let result = canvas.result(of: drag(.resize(id: "a", corner: .se, original: box), handle, CGPoint(x: 0, y: 0)))
    #expect(result == BBox(y0: 200, x0: 100, y1: 220, x1: 120))
  }

  @Test func theTagOfASelectedBoxIsPressedFirst() {
    let box = BBox(y0: 400, x0: 100, y1: 800, x1: 500)
    let items = [item("a", box)]
    let tag = canvas.tagRect(for: items[0])
    #expect(canvas.begin(at: CGPoint(x: tag.midX, y: tag.midY), items: items, selected: "a") == .tag(id: "a"))
  }

  @Test func aTopmostBoxWinsWhereBoxesOverlap() {
    let low = item("low", BBox(y0: 100, x0: 100, y1: 700, x1: 700))
    let high = item("high", BBox(y0: 300, x0: 300, y1: 900, x1: 900))
    let mode = canvas.begin(at: CGPoint(x: 200, y: 100), items: [low, high], selected: nil)
    #expect(mode == .move(id: "high", original: high.box))
  }

  @Test func theCanvasFitsTheProportionsOfTheGeneration() {
    #expect(CanvasGeometry.fit(aspect: 2, in: CGSize(width: 400, height: 400)) == CGSize(width: 400, height: 200))
    #expect(CanvasGeometry.fit(aspect: 0.5, in: CGSize(width: 400, height: 200)) == CGSize(width: 100, height: 200))
    #expect(CanvasGeometry.fit(aspect: .nan, in: CGSize(width: 300, height: 300)) == CGSize(width: 300, height: 300))
  }

  @Test func generationSizeReadsTheContext() {
    let message = Data(#"{"type":"context","parameters":{"width":1536,"height":1024}}"#.utf8)
    #expect(GenerationSize.read(fromContext: message) == CGSize(width: 1536, height: 1024))
  }
}
