import CoreGraphics
import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The geometry of the canvas")
struct CanvasGeometryTests {
  /// A canvas of 500 × 250 points: 1 point of width is 2 grid units, 1 point of height is 4.
  private let canvas = CanvasGeometry(size: CGSize(width: 500, height: 250))

  private func item(_ id: Int, _ box: BBox, number: Int? = nil, type: ElementType = .obj) -> CanvasItem {
    CanvasItem(id: id, number: number ?? id, type: type, box: box)
  }

  private func drag(_ mode: CanvasMode, _ start: CGPoint, _ end: CGPoint) -> CanvasDrag {
    CanvasDrag(mode: mode, start: start, current: end)
  }

  // MARK: Points and the grid

  @Test func pointsBecomGridUnitsAndStayInsideTheGrid() {
    let middle = canvas.grid(CGPoint(x: 250, y: 125))
    #expect(middle.x == 500 && middle.y == 500)
    let outside = canvas.grid(CGPoint(x: -30, y: 900))
    #expect(outside.x == 0 && outside.y == 1000)
    let moved = canvas.delta(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: -25))
    #expect(moved.dx == 200 && moved.dy == -100)
  }

  @Test func aBoxAndAGridRectBecomePointsAndBack() {
    let rect = canvas.rect(of: BBox(y0: 200, x0: 100, y1: 600, x1: 500))
    #expect(rect == CGRect(x: 50, y: 50, width: 200, height: 100))
    #expect(canvas.rect(of: GridRect(y0: 200, x0: 100, y1: 600, x1: 500)) == rect)
    #expect(canvas.handlePoint(.nw, of: rect) == CGPoint(x: 50, y: 50) && canvas.handlePoint(.se, of: rect) == CGPoint(x: 250, y: 150))
    #expect(canvas.handlePoint(.ne, of: rect) == CGPoint(x: 250, y: 50) && canvas.handlePoint(.sw, of: rect) == CGPoint(x: 50, y: 150))
  }

  @Test func aCanvasWithoutSizeDoesNothingAndDrawsNothing() {
    let none = CanvasGeometry(size: .zero)
    #expect(none.grid(CGPoint(x: 5, y: 5)).x == 0 && none.delta(from: .zero, to: CGPoint(x: 5, y: 5)).dx == 0)
    #expect(none.begin(at: CGPoint(x: 1, y: 1), items: [item(1, BBox(y0: 0, x0: 0, y1: 1000, x1: 1000))], selected: 1) == .draw)
  }

  // MARK: Where a press begins

  private var first: CanvasItem { item(1, BBox(y0: 200, x0: 100, y1: 600, x1: 500)) }  // 50,50 – 250,150 points
  private var second: CanvasItem { item(2, BBox(y0: 400, x0: 300, y1: 800, x1: 700)) }  // 150,100 – 350,200 points

  @Test func aPressOnEmptyCanvasDrawsAndOnABoxMovesIt() {
    #expect(canvas.begin(at: CGPoint(x: 400, y: 20), items: [first, second], selected: nil) == .draw)
    #expect(canvas.begin(at: CGPoint(x: 100, y: 100), items: [first, second], selected: nil) == .move(id: 1, original: first.box))
  }

  @Test func whereBoxesOverlapTheTopmostWinsAndTheSelectedOneBeatsThem() {
    let overlap = CGPoint(x: 200, y: 130)  // inside both
    #expect(canvas.begin(at: overlap, items: [first, second], selected: nil) == .move(id: 2, original: second.box))
    #expect(canvas.begin(at: overlap, items: [first, second], selected: 1) == .move(id: 1, original: first.box))
  }

  @Test func theCornersOfTheSelectedBoxResizeItAndOnlyTheSelectedOnes() {
    let corner = CGPoint(x: 248, y: 148)  // just inside the south-east corner of the first box
    #expect(canvas.begin(at: corner, items: [first], selected: 1) == .resize(id: 1, corner: .se, original: first.box))
    #expect(canvas.begin(at: corner, items: [first], selected: nil) == .move(id: 1, original: first.box))
    #expect(canvas.begin(at: CGPoint(x: 49, y: 51), items: [first], selected: 1) == .resize(id: 1, corner: .nw, original: first.box))
    #expect(canvas.begin(at: CGPoint(x: 250, y: 50), items: [first], selected: 1) == .resize(id: 1, corner: .ne, original: first.box))
    #expect(canvas.begin(at: CGPoint(x: 50, y: 150), items: [first], selected: 1) == .resize(id: 1, corner: .sw, original: first.box))
    // Too far from every corner: a move.
    #expect(canvas.begin(at: CGPoint(x: 150, y: 100), items: [first], selected: 1) == .move(id: 1, original: first.box))
  }

  @Test func aTagIsAboveTheTopLeftCornerOrInsideWhenThereIsNoRoomAndNeverBeyondTheRightEdge() {
    let tag = canvas.tagRect(for: first)
    #expect(tag.minX == 50 && tag.maxY <= 50 && tag.height == CanvasGeometry.tagHeight && tag.minY >= 0)
    let top = item(3, BBox(y0: 0, x0: 0, y1: 400, x1: 400))
    #expect(canvas.tagRect(for: top).minY == 2)  // inside the box
    let right = item(4, BBox(y0: 600, x0: 900, y1: 900, x1: 1000))
    #expect(canvas.tagRect(for: right).maxX <= 500 && canvas.tagRect(for: right).minX >= 0)
    #expect(first.label == "E1 · obj" && item(2, first.box, number: 12, type: .text).label == "E12 · text")
  }

  @Test func aPressOnATagStartsTheTagGestureBeforeTheBoxAndTheCornersOfTheSelectedBoxComeFirst() {
    let tag = canvas.tagRect(for: first)
    let onTag = CGPoint(x: tag.midX, y: tag.midY)
    #expect(canvas.begin(at: onTag, items: [first], selected: nil) == .tag(id: 1))
    #expect(canvas.begin(at: onTag, items: [first], selected: 1) == .tag(id: 1))
    // A tag in front of another box is the one that is hit.
    #expect(canvas.begin(at: onTag, items: [first, item(5, BBox(y0: 0, x0: 0, y1: 1000, x1: 1000))], selected: nil) == .tag(id: 1))
  }

  @Test func theTagOfTheSelectedBoxWinsWhereTagsOverlapAndOverItsOwnCornerHandles() {
    // Two boxes touching the top edge at the same x: both tags sit inside the boxes at the same place.
    let small = item(1, BBox(y0: 0, x0: 0, y1: 500, x1: 500))
    let big = item(2, BBox(y0: 0, x0: 0, y1: 1000, x1: 1000))
    let onTag = CGPoint(x: canvas.tagRect(for: small).midX, y: canvas.tagRect(for: small).midY)
    #expect(canvas.begin(at: onTag, items: [small, big], selected: nil) == .tag(id: 2))  // the topmost
    #expect(canvas.begin(at: onTag, items: [small, big], selected: 1) == .tag(id: 1))  // the selected one is drawn on top
    // The tag of a selected box that touches the top edge covers the north-west handle: the tag wins.
    let cornerOfTag = CGPoint(x: canvas.tagRect(for: small).minX + 2, y: canvas.tagRect(for: small).minY + 2)
    #expect(canvas.begin(at: cornerOfTag, items: [small], selected: 1) == .tag(id: 1))
    // Away from the tag the handle still resizes.
    let handle = canvas.handlePoint(.se, of: canvas.rect(of: small.box))
    #expect(canvas.begin(at: handle, items: [small], selected: 1) == .resize(id: 1, corner: .se, original: small.box))
  }

  // MARK: Drawing

  @Test func drawingMakesABoxFromTwoCornersInAnyDirectionInsideTheGrid() {
    let down = drag(.draw, CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150))
    #expect(canvas.result(of: down) == BBox(y0: 200, x0: 200, y1: 600, x1: 400))
    let up = drag(.draw, CGPoint(x: 200, y: 150), CGPoint(x: 100, y: 50))
    #expect(canvas.result(of: up) == canvas.result(of: down))
    let beyond = drag(.draw, CGPoint(x: 400, y: 200), CGPoint(x: 900, y: 700))
    #expect(canvas.result(of: beyond) == BBox(y0: 800, x0: 800, y1: 1000, x1: 1000))
  }

  @Test func aDrawnBoxWithASideUnder20IsDiscardedButTheGhostIsStillShown() {
    let thin = drag(.draw, CGPoint(x: 100, y: 50), CGPoint(x: 104, y: 150))  // 8 grid units wide
    #expect(canvas.result(of: thin) == nil)
    #expect(canvas.preview(of: thin) == GridRect(y0: 200, x0: 200, y1: 600, x1: 208))
    let click = drag(.draw, CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 50))
    #expect(canvas.result(of: click) == nil && !click.moved)
    let edge = drag(.draw, CGPoint(x: 100, y: 50), CGPoint(x: 110, y: 55))  // exactly 20 × 20
    #expect(canvas.result(of: edge) == BBox(y0: 200, x0: 200, y1: 220, x1: 220))
  }

  // MARK: Moving

  @Test func movingKeepsTheSizeAndStopsAtTheEdgesOfTheCanvas() {
    let box = first.box  // 400 high, 400 wide
    let right = drag(.move(id: 1, original: box), CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 125))  // +100, +100
    #expect(canvas.result(of: right) == BBox(y0: 300, x0: 200, y1: 700, x1: 600))
    let far = drag(.move(id: 1, original: box), CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 900))
    #expect(canvas.result(of: far) == BBox(y0: 600, x0: 600, y1: 1000, x1: 1000))
    let back = drag(.move(id: 1, original: box), CGPoint(x: 100, y: 100), CGPoint(x: -900, y: -900))
    #expect(canvas.result(of: back) == BBox(y0: 0, x0: 0, y1: 400, x1: 400))
    #expect(canvas.preview(of: right) == GridRect(y0: 300, x0: 200, y1: 700, x1: 600))
  }

  @Test func aMoveOfNoDistanceLeavesTheBoxAsItWas() {
    let still = drag(.move(id: 1, original: first.box), CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 100))
    #expect(canvas.result(of: still) == first.box && !still.moved)
    #expect(drag(.draw, .zero, CGPoint(x: 3, y: 0)).moved && !drag(.draw, .zero, CGPoint(x: 2, y: 2)).moved)
  }

  // MARK: Resizing

  @Test func resizingMovesOneCornerAndTheOppositeOneStaysFixed() {
    let box = first.box  // y 200–600, x 100–500
    func resize(_ corner: CanvasCorner, to point: CGPoint) -> BBox? {
      canvas.result(of: drag(.resize(id: 1, corner: corner, original: box), .zero, point))
    }
    #expect(resize(.se, to: CGPoint(x: 300, y: 200)) == BBox(y0: 200, x0: 100, y1: 800, x1: 600))
    #expect(resize(.nw, to: CGPoint(x: 25, y: 25)) == BBox(y0: 100, x0: 50, y1: 600, x1: 500))
    #expect(resize(.ne, to: CGPoint(x: 300, y: 25)) == BBox(y0: 100, x0: 100, y1: 600, x1: 600))
    #expect(resize(.sw, to: CGPoint(x: 25, y: 200)) == BBox(y0: 200, x0: 50, y1: 800, x1: 500))
  }

  @Test func resizingStopsAtTheMinimumSideAndAtTheEdgesAndNeverFlips() {
    let box = first.box
    func resize(_ corner: CanvasCorner, to point: CGPoint) -> BBox? {
      canvas.result(of: drag(.resize(id: 1, corner: corner, original: box), .zero, point))
    }
    // Dragging the south-east corner past the north-west one leaves the minimum side.
    #expect(resize(.se, to: CGPoint(x: 0, y: 0)) == BBox(y0: 200, x0: 100, y1: 220, x1: 120))
    #expect(resize(.nw, to: CGPoint(x: 400, y: 200)) == BBox(y0: 580, x0: 480, y1: 600, x1: 500))
    #expect(resize(.se, to: CGPoint(x: 9999, y: 9999)) == BBox(y0: 200, x0: 100, y1: 1000, x1: 1000))
    #expect(resize(.nw, to: CGPoint(x: -50, y: -50)) == BBox(y0: 0, x0: 0, y1: 600, x1: 500))
  }

  @Test func aPressOnATagMakesNoBox() {
    let press = drag(.tag(id: 1), CGPoint(x: 60, y: 40), CGPoint(x: 400, y: 200))
    #expect(canvas.result(of: press) == nil && canvas.preview(of: press) == nil)
  }

  // MARK: The shape of the canvas

  @Test func theCanvasHasTheProportionsOfTheGenerationAndFitsTheRoom() {
    let room = CGSize(width: 600, height: 300)
    #expect(CanvasGeometry.fit(aspect: 1, in: room) == CGSize(width: 300, height: 300))
    #expect(CanvasGeometry.fit(aspect: 2, in: room) == CGSize(width: 600, height: 300))
    #expect(CanvasGeometry.fit(aspect: 4, in: room) == CGSize(width: 600, height: 150))
    #expect(CanvasGeometry.fit(aspect: 0.5, in: room) == CGSize(width: 150, height: 300))
    for nonsense in [0.0, -1, .infinity, .nan] { #expect(CanvasGeometry.fit(aspect: nonsense, in: room) == CGSize(width: 300, height: 300), "\(nonsense)") }
    #expect(CanvasGeometry.fit(aspect: 1, in: .zero) == .zero)
  }

  @Test func theSizeOfTheGenerationIsReadFromTheContext() {
    func context(_ parameters: String) -> Data { Data(#"{"type": "context", "family": "ideogram_4", "parameters": \#(parameters)}"#.utf8) }
    #expect(GenerationSize.read(fromContext: context(#"{"width": 1024, "height": 576}"#)) == CGSize(width: 1024, height: 576))
    #expect(GenerationSize.read(fromContext: context(#"{"width": 0, "height": 576}"#)) == nil)
    #expect(GenerationSize.read(fromContext: context(#"{"width": "wide"}"#)) == nil)
    #expect(GenerationSize.read(fromContext: Data(#"{"type": "context"}"#.utf8)) == nil)
    #expect(GenerationSize.read(fromContext: Data("garbage".utf8)) == nil)
  }
}
