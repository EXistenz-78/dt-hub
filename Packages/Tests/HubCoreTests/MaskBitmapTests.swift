import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

struct MaskBitmapTests {
  func painted(_ bitmap: MaskBitmap, _ x: Int, _ y: Int) -> Bool { bitmap.pixels[y * bitmap.width + x] >= 128 }

  @Test func theWorkingSizeKeepsTheRatioAndCapsTheLongestSide() {
    #expect(MaskBitmap.workingSize(imageWidth: 4000, imageHeight: 2000) == (1024, 512))
    #expect(MaskBitmap.workingSize(imageWidth: 600, imageHeight: 800) == (600, 800))
    #expect(MaskBitmap.workingSize(imageWidth: 1000, imageHeight: 3000) == (341, 1024))
  }

  @Test func aNewMaskIsEmpty() {
    let mask = MaskBitmap(width: 40, height: 30)
    #expect(mask.isEmpty)
    #expect(mask.coverage == 0)
  }

  @Test func theBrushPaintsARoundSpot() {
    var mask = MaskBitmap(width: 100, height: 100)
    mask.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 10, erase: false)
    #expect(painted(mask, 50, 50))
    #expect(painted(mask, 58, 50))
    #expect(!painted(mask, 62, 50))
    // Round, not square: the corner of the square around the spot is clear.
    #expect(!painted(mask, 58, 58))
    #expect(!mask.isEmpty)
  }

  @Test func aStrokeLeavesNoGapBetweenItsEnds() {
    var mask = MaskBitmap(width: 200, height: 40)
    mask.stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 180, y: 20), radius: 4, erase: false)
    for x in 20...180 { #expect(painted(mask, x, 20)) }
    #expect(!painted(mask, 100, 30))
  }

  @Test func theEraserTakesPaintAwayAndLeavesTheRest() {
    var mask = MaskBitmap(width: 100, height: 100)
    mask.stroke(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 80, y: 50), radius: 8, erase: false)
    mask.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 8, erase: true)
    #expect(!painted(mask, 50, 50))
    #expect(painted(mask, 30, 50))
    #expect(painted(mask, 70, 50))
  }

  @Test func theBrushStaysInsideTheMask() {
    var mask = MaskBitmap(width: 50, height: 50)
    mask.stroke(from: CGPoint(x: -30, y: -30), to: CGPoint(x: 5, y: 5), radius: 6, erase: false)
    mask.stroke(from: CGPoint(x: 45, y: 45), to: CGPoint(x: 90, y: 90), radius: 6, erase: false)
    #expect(painted(mask, 0, 0))
    #expect(painted(mask, 49, 49))
    mask.stroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 6, erase: false)
  }

  @Test func invertingSwapsPaintedAndClear() {
    var mask = MaskBitmap(width: 20, height: 20)
    mask.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), radius: 3, erase: false)
    let before = mask.coverage
    mask.invert()
    #expect(abs(mask.coverage - (1 - before)) < 0.01)
    #expect(!painted(mask, 5, 5))
    #expect(painted(mask, 19, 19))
  }

  @Test func clearingEmptiesTheMask() {
    var mask = MaskBitmap(width: 20, height: 20)
    mask.invert()
    #expect(mask.coverage == 1)
    mask.clear()
    #expect(mask.isEmpty)
  }

  @Test func theCoverageIsTheShareOfPaintedPixels() {
    var mask = MaskBitmap(width: 10, height: 10)
    for y in 0..<10 { mask.stroke(from: CGPoint(x: 0.5, y: Double(y) + 0.5), to: CGPoint(x: 4.5, y: Double(y) + 0.5), radius: 0.6, erase: false) }
    #expect(mask.coverage > 0.4 && mask.coverage < 0.6)
  }

  @Test func aPNGBringsTheSameMaskBack() throws {
    var mask = MaskBitmap(width: 64, height: 48)
    mask.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30), radius: 5, erase: false)
    let data = try #require(mask.pngData())
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let back = try #require(MaskBitmap(image: image))
    #expect(back.width == 64 && back.height == 48)
    #expect(back == mask)
  }
  @Test func aClipStopsTheBrushAtItsEdge() throws {
    var mask = MaskBitmap(width: 100, height: 100)
    // Only the pixels whose centre is inside the clip (x 40…80, y 20…60) are painted.
    let dirty = mask.stroke(
      from: CGPoint(x: 10, y: 40), to: CGPoint(x: 90, y: 40), radius: 8, erase: false,
      clip: CGRect(x: 40, y: 20, width: 40, height: 40))
    #expect(painted(mask, 60, 40))
    #expect(!painted(mask, 30, 40) && !painted(mask, 85, 40) && !painted(mask, 60, 15))
    let touched = try #require(dirty)
    #expect(touched.minX >= 40 && touched.maxX <= 80 && touched.minY >= 20 && touched.maxY <= 60)
    // A stroke wholly outside the clip touches nothing.
    #expect(mask.stroke(from: CGPoint(x: 5, y: 90), to: CGPoint(x: 20, y: 90), radius: 3, erase: false, clip: CGRect(x: 40, y: 20, width: 40, height: 40)) == nil)
  }

  @Test func aStrokeReportsTheRectangleItTouched() throws {
    var mask = MaskBitmap(width: 100, height: 100)
    let dirtyResult = mask.stroke(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 60, y: 40), radius: 5, erase: false)
    let dirty = try #require(dirtyResult)
    #expect(dirty.minX <= 25 && dirty.maxX >= 65 && dirty.minY <= 35 && dirty.maxY >= 45)
    #expect(dirty.width < 60 && dirty.height < 20)
    // A segment out of the mask touches nothing.
    #expect(mask.stroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 5, erase: false) == nil)
  }
}

struct MaskOverlayTests {
  func bytes(_ overlay: MaskOverlay) throws -> [UInt8] {
    let image = try #require(overlay.image())
    return Array(try #require(image.dataProvider?.data as Data?))
  }

  @Test func theOverlayIsClearWhereNothingIsPainted() throws {
    var mask = MaskBitmap(width: 10, height: 10)
    mask.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), radius: 2, erase: false)
    let overlay = try #require(MaskOverlay(width: 10, height: 10, red: 255, green: 140, blue: 0, opacity: 0.5))
    overlay.rebuild(from: mask)
    let image = try #require(overlay.image())
    #expect(image.width == 10 && image.height == 10)
    let data = try bytes(overlay)
    #expect(data[3] == 0)  // top-left corner: nothing painted
    let centre = (5 * 10 + 5) * 4
    #expect(data[centre + 3] > 100)
    #expect(data[centre] > data[centre + 2])  // orange: more red than blue
  }

  @Test func updatingOnlyWhatAStrokeTouchedGivesTheSameOverlayAsRebuilding() throws {
    var mask = MaskBitmap(width: 120, height: 80)
    let incremental = try #require(MaskOverlay(width: 120, height: 80, red: 255, green: 140, blue: 0, opacity: 0.55))
    for step in 0..<8 {
      let start = CGPoint(x: 10 + Double(step) * 12, y: 20 + Double(step) * 5)
      let dirtyResult = mask.stroke(from: start, to: CGPoint(x: start.x + 20, y: start.y + 3), radius: 6, erase: step % 3 == 2)
      let dirty = try #require(dirtyResult)
      incremental.update(from: mask, rect: dirty)
    }
    let whole = try #require(MaskOverlay(width: 120, height: 80, red: 255, green: 140, blue: 0, opacity: 0.55))
    whole.rebuild(from: mask)
    #expect(try bytes(incremental) == bytes(whole))
  }

  @Test func anOverlayOfAnotherSizeIsLeftAlone() throws {
    let overlay = try #require(MaskOverlay(width: 10, height: 10, red: 1, green: 2, blue: 3, opacity: 1))
    var mask = MaskBitmap(width: 20, height: 20)
    mask.invert()
    overlay.rebuild(from: mask)
    #expect(try bytes(overlay).allSatisfy { $0 == 0 })
  }
}

struct MaskGeometryTests {
  @Test func theWholeImageInTheViewMapsCornerToCorner() {
    let mask = MaskBitmap(width: 100, height: 50)
    let crop = CGRect(x: 0, y: 0, width: 200, height: 100)
    let view = CGSize(width: 400, height: 200)
    #expect(mask.point(forViewPoint: .zero, viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 0, y: 0))
    #expect(mask.point(forViewPoint: CGPoint(x: 400, y: 200), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 100, y: 50))
    #expect(mask.point(forViewPoint: CGPoint(x: 200, y: 100), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 50, y: 25))
  }

  @Test func aCutShowsOnlyItsPartOfTheMask() {
    let mask = MaskBitmap(width: 100, height: 50)
    // The right half of a 200×100 image fills the view.
    let crop = CGRect(x: 100, y: 0, width: 100, height: 100)
    let view = CGSize(width: 100, height: 100)
    #expect(mask.point(forViewPoint: .zero, viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 50, y: 0))
    #expect(mask.point(forViewPoint: CGPoint(x: 100, y: 100), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 100, y: 50))
  }

  @Test func theBrushIsMeasuredOnTheCanvas() {
    let mask = MaskBitmap(width: 512, height: 512)
    // A 1024-pixel image shown whole on a 1024 canvas, mask at half size: a 100 px brush is 25 mask px of radius.
    let crop = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    #expect(mask.brushRadius(diameter: 100, canvasWidth: 1024, crop: crop, imageWidth: 1024) == 25)
    // A cut of half the image on the same canvas magnifies it: the same brush covers half as much of the image.
    let cut = CGRect(x: 0, y: 0, width: 512, height: 1024)
    #expect(mask.brushRadius(diameter: 100, canvasWidth: 1024, crop: cut, imageWidth: 1024) == 12.5)
  }
}
