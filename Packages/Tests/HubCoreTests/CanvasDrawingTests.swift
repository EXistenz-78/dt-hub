import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct CanvasDrawingTests {
  func store() throws -> ControlStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasDrawingTests-\(UUID())", isDirectory: true)
    let store = ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
    try store.setImage(data: pictureData(width: 400, height: 300), name: "a.png", source: .pasteboard)
    return store
  }

  let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
  let view = CGSize(width: 400, height: 300)

  func drag(
    _ drawing: CanvasDrawing, _ tool: DrawingTool, through points: [CGPoint], into control: ControlStore,
    color: (red: UInt8, green: UInt8, blue: UInt8) = (200, 20, 20)
  ) throws {
    for point in points {
      drawing.stroke(
        tool: tool, to: point, viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 20, color: color)
    }
    try drawing.endStroke(into: control)
  }

  @Test func withoutAnImageThereIsNothingToShow() throws {
    let drawing = CanvasDrawing()
    let empty = ControlStore(
      storage: FileReferenceStorage(folder: FileManager.default.temporaryDirectory.appendingPathComponent("CD-\(UUID())")),
      fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("cd-\(UUID()).json"))
    drawing.sync(with: empty)
    #expect(drawing.maskImage == nil && drawing.paintImage == nil)
    // Drawing does nothing.
    drawing.stroke(tool: .maskAdd, to: .zero, viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 10, color: (0, 0, 0))
    #expect(!drawing.isStroking)
  }

  @Test func aMaskStrokeShowsAtOnceAndEndsInTheStore() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    #expect(drawing.maskImage == nil)
    drawing.stroke(tool: .maskAdd, to: CGPoint(x: 100, y: 100), viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 20, color: (0, 0, 0))
    #expect(drawing.isStroking)
    #expect(drawing.maskImage != nil)
    #expect(control.inputs.mask == nil)  // not yet: the stroke is not over
    drawing.stroke(tool: .maskAdd, to: CGPoint(x: 200, y: 100), viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 20, color: (0, 0, 0))
    try drawing.endStroke(into: control)
    #expect(!drawing.isStroking)
    let reference = try #require(control.inputs.mask)
    #expect(reference.coverage > 0)
    let bitmap = try #require(control.maskBitmap())
    // The stroke reaches the last point (the end is carried to it) and the middle.
    #expect(bitmap.pixels[100 * bitmap.width + 200] >= 128)
    #expect(bitmap.pixels[100 * bitmap.width + 150] >= 128)
    #expect(bitmap.pixels[250 * bitmap.width + 50] == 0)
  }

  @Test func aStrokeCommittedHereIsNotReadBack() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    let shown = drawing.maskImage
    drawing.sync(with: control)
    #expect(drawing.maskImage === shown)
  }

  @Test func undoAndRedoBringTheMaskBack() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    control.undo()
    drawing.sync(with: control)
    #expect(drawing.maskImage == nil)
    control.redo()
    drawing.sync(with: control)
    #expect(drawing.maskImage != nil)
  }

  @Test func theEraserTakesTheMaskAway() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 150), CGPoint(x: 350, y: 150)], into: control)
    let before = try #require(control.inputs.mask).coverage
    try drag(drawing, .maskRemove, through: [CGPoint(x: 150, y: 150), CGPoint(x: 250, y: 150)], into: control)
    #expect(try #require(control.inputs.mask).coverage < before)
  }

  @Test func theBrushDrawsInTheChosenColour() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .brush, through: [CGPoint(x: 100, y: 100), CGPoint(x: 220, y: 100)], into: control, color: (10, 200, 30))
    #expect(drawing.paintImage != nil)
    #expect(control.inputs.mask == nil)
    let layer = try #require(control.paintBitmap())
    #expect(layer.alpha(x: 150, y: 100) == 255)
    #expect(layer.color(x: 150, y: 100).green == 200)
  }

  @Test func aSparseStrokeIsCurvedNotCornered() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    // Three far-apart points: a straight join would pass (200, 50) → (200, 250) with a sharp corner at (200, 50);
    // the smoothed stroke does not reach the corner pixel with a thin brush.
    for point in [CGPoint(x: 20, y: 50), CGPoint(x: 200, y: 50), CGPoint(x: 200, y: 250)] {
      drawing.stroke(tool: .brush, to: point, viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 6, color: (255, 0, 0))
    }
    try drawing.endStroke(into: control)
    let layer = try #require(control.paintBitmap())
    #expect(layer.alpha(x: 20, y: 50) == 255)  // starts at the first point
    #expect(layer.alpha(x: 200, y: 250) == 255)  // and the end reaches the last one
    #expect(layer.alpha(x: 200, y: 50) == 0)  // the corner is rounded off
    // The curve goes from the middle (110, 50) through the corner's side to the middle (200, 150): at its
    // own middle it is at (177.5, 75).
    #expect(layer.alpha(x: 177, y: 75) == 255)
  }

  @Test func aNewImageStartsClean() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    try drag(drawing, .brush, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    try control.setImage(data: pictureData(width: 100, height: 100), name: "b.png", source: .pasteboard)
    drawing.sync(with: control)
    #expect(drawing.maskImage == nil && drawing.paintImage == nil)
  }
}
