import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import HubCore

struct PaintBitmapTests {
  @Test func aNewDrawingIsEmpty() {
    #expect(PaintBitmap(width: 20, height: 10).isEmpty)
  }

  @Test func theBrushDrawsARoundSpotInTheChosenColour() {
    var paint = PaintBitmap(width: 100, height: 100)
    paint.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 10, red: 200, green: 30, blue: 20)
    #expect(!paint.isEmpty)
    #expect(paint.alpha(x: 50, y: 50) == 255)
    let colour = paint.color(x: 50, y: 50)
    #expect(colour.red == 200 && colour.green == 30 && colour.blue == 20)
    #expect(paint.alpha(x: 58, y: 50) == 255)
    #expect(paint.alpha(x: 63, y: 50) == 0)
    #expect(paint.alpha(x: 58, y: 58) == 0)
  }

  @Test func aNewColourPaintsOverTheOldOne() {
    var paint = PaintBitmap(width: 60, height: 20)
    paint.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10), radius: 5, red: 255, green: 0, blue: 0)
    paint.stroke(from: CGPoint(x: 30, y: 10), to: CGPoint(x: 30, y: 10), radius: 5, red: 0, green: 0, blue: 255)
    #expect(paint.color(x: 30, y: 10).blue == 255)
    #expect(paint.color(x: 15, y: 10).red == 255)
  }

  @Test func goingOverTheSamePlaceAgainKeepsTheEdgeAsItWas() {
    var once = PaintBitmap(width: 60, height: 30)
    once.stroke(from: CGPoint(x: 10, y: 15), to: CGPoint(x: 50, y: 15), radius: 6, red: 10, green: 20, blue: 30)
    var twice = once
    twice.stroke(from: CGPoint(x: 10, y: 15), to: CGPoint(x: 50, y: 15), radius: 6, red: 10, green: 20, blue: 30)
    #expect(once == twice)
  }

  @Test func theBrushStaysInsideTheDrawing() {
    var paint = PaintBitmap(width: 30, height: 30)
    paint.stroke(from: CGPoint(x: -20, y: -20), to: CGPoint(x: 3, y: 3), radius: 5, red: 1, green: 2, blue: 3)
    paint.stroke(from: CGPoint(x: 400, y: 400), to: CGPoint(x: 500, y: 500), radius: 5, red: 1, green: 2, blue: 3)
    #expect(paint.alpha(x: 0, y: 0) == 255)
  }

  @Test func clearingEmptiesTheDrawing() {
    var paint = PaintBitmap(width: 20, height: 20)
    paint.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 15, y: 15), radius: 3, red: 9, green: 9, blue: 9)
    paint.clear()
    #expect(paint.isEmpty)
  }

  @Test func aPNGBringsTheDrawingBack() throws {
    var paint = PaintBitmap(width: 64, height: 48)
    paint.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30), radius: 6, red: 220, green: 40, blue: 10)
    let data = try #require(paint.pngData())
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let back = try #require(PaintBitmap(image: image))
    #expect(back.width == 64 && back.height == 48)
    // The core of the stroke comes back exactly; the empty corner is still empty.
    #expect(back.alpha(x: 30, y: 20) == 255)
    #expect(back.color(x: 30, y: 20).red == 220 && back.color(x: 30, y: 20).green == 40)
    #expect(back.alpha(x: 60, y: 2) == 0)
  }

  @Test func updatingOnlyWhatAStrokeTouchedGivesTheSameOverlayAsRebuilding() throws {
    var paint = PaintBitmap(width: 120, height: 80)
    let incremental = try #require(PaintOverlay(width: 120, height: 80))
    for step in 0..<6 {
      let start = CGPoint(x: 10 + Double(step) * 15, y: 15 + Double(step) * 8)
      let dirtyResult = paint.stroke(
        from: start, to: CGPoint(x: start.x + 25, y: start.y + 4), radius: 6, red: UInt8(40 * step), green: 90, blue: 200)
      let dirty = try #require(dirtyResult)
      incremental.update(from: paint, rect: dirty)
    }
    let whole = try #require(PaintOverlay(width: 120, height: 80))
    whole.rebuild(from: paint)
    func bytes(_ overlay: PaintOverlay) throws -> [UInt8] {
      Array(try #require(overlay.image()?.dataProvider?.data as Data?))
    }
    #expect(try bytes(incremental) == bytes(whole))
  }

  @Test func aClipStopsTheBrushAtItsEdge() {
    var paint = PaintBitmap(width: 100, height: 100)
    paint.stroke(
      from: CGPoint(x: 10, y: 40), to: CGPoint(x: 90, y: 40), radius: 8, red: 9, green: 9, blue: 9,
      clip: CGRect(x: 40, y: 20, width: 40, height: 40))
    #expect(paint.alpha(x: 60, y: 40) == 255)
    #expect(paint.alpha(x: 30, y: 40) == 0 && paint.alpha(x: 85, y: 40) == 0 && paint.alpha(x: 60, y: 15) == 0)
  }

  @Test func aStrokeReportsTheRectangleItTouched() throws {
    var paint = PaintBitmap(width: 100, height: 100)
    let dirtyResult = paint.stroke(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 60, y: 40), radius: 5, red: 1, green: 2, blue: 3)
    let dirty = try #require(dirtyResult)
    #expect(dirty.minX <= 25 && dirty.maxX >= 65 && dirty.width < 60 && dirty.height < 20)
    #expect(paint.stroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 5, red: 1, green: 2, blue: 3) == nil)
  }
}
