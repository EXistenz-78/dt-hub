import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// The rotation of the start image in the canvas (about the centre of the image, clockwise, in degrees).
struct RotationTests {
  func halves() -> CGImage {  // 100×100, left half red, right half blue
    let context = CGContext(
      data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
    return context.makeImage()!
  }

  func sample(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return bytes.map(Int.init)
  }

  func isRed(_ p: [Int]) -> Bool { p[0] > 240 && p[2] < 15 }
  func isBlue(_ p: [Int]) -> Bool { p[2] > 240 && p[0] < 15 }

  // MARK: Framing

  @Test func rotationIsClampedAndOldFilesReadAsZero() throws {
    #expect(Framing(rotation: 400).clamped().rotation == 180)
    #expect(Framing(rotation: -400).clamped().rotation == -180)
    let old = try JSONDecoder().decode(Framing.self, from: Data(#"{"zoom":10,"offsetX":0.5,"offsetY":0}"#.utf8))
    #expect(old.rotation == 0 && old.zoom == 10)
    #expect(Framing(rotation: 12) != Framing())
  }

  // MARK: Geometry

  @Test func aQuarterTurnOnASquareStillCoversTheCanvasAndFortyFiveDoesNot() {
    let q = FramingMath.margins(
      imageWidth: 100, imageHeight: 100, canvasWidth: 100, canvasHeight: 100, framing: Framing(rotation: 90))
    #expect(q.isEmpty)
    let d = FramingMath.margins(
      imageWidth: 100, imageHeight: 100, canvasWidth: 100, canvasHeight: 100, framing: Framing(rotation: 45))
    #expect(!d.isEmpty)
    let none = FramingMath.margins(
      imageWidth: 100, imageHeight: 100, canvasWidth: 100, canvasHeight: 100, framing: Framing())
    #expect(none.isEmpty)
  }

  @Test func aCanvasPointGoesBackToTheImagePoint() {
    // 90° clockwise: the top-left corner of the canvas shows what is at the bottom-left of the image.
    let p = FramingMath.imagePoint(
      forCanvasFraction: CGPoint(x: 0, y: 0), imageWidth: 100, imageHeight: 100, canvasWidth: 100, canvasHeight: 100,
      framing: Framing(rotation: 90))
    #expect(abs(p.x - 0) < 0.001 && abs(p.y - 100) < 0.001)
    let same = FramingMath.imagePoint(
      forCanvasFraction: CGPoint(x: 0.25, y: 0.5), imageWidth: 100, imageHeight: 100, canvasWidth: 100,
      canvasHeight: 100, framing: Framing())
    #expect(abs(same.x - 25) < 0.001 && abs(same.y - 50) < 0.001)
  }

  // MARK: The framed image

  @Test func aQuarterTurnPutsTheLeftHalfOnTop() throws {
    let framed = try #require(
      InputComposer.frame(halves(), toWidth: 100, height: 100, framing: Framing(rotation: 90)))
    #expect(isRed(sample(framed, 50, 10)) && isBlue(sample(framed, 50, 90)))
  }

  @Test func theCornersTheRotationLeavesTakeTheColourOfTheNearestEdge() throws {
    let framed = try #require(
      InputComposer.frame(halves(), toWidth: 100, height: 100, framing: Framing(rotation: 45)))
    #expect(isRed(sample(framed, 2, 50)) || isBlue(sample(framed, 2, 50)))
    let corner = sample(framed, 1, 1)
    #expect(isRed(corner) || isBlue(corner), "not black, not grey: \(corner)")
  }

  @Test func theMaskRegeneratesTheCornersOfARotatedImage() throws {
    let mask = try #require(
      InputComposer.mask(nil, imageWidth: 100, imageHeight: 100, toWidth: 100, height: 100, framing: Framing(rotation: 45)))
    #expect(sample(mask, 1, 1)[3] == 0, "regenerated")
    #expect(sample(mask, 50, 50)[3] == 255, "kept")
  }

  @Test func theMaskOfAQuarterTurnIsAllKept() throws {
    let mask = try #require(
      InputComposer.mask(nil, imageWidth: 100, imageHeight: 100, toWidth: 100, height: 100, framing: Framing(rotation: 90)))
    #expect(sample(mask, 1, 1)[3] == 255 && sample(mask, 98, 98)[3] == 255)
  }

  // MARK: Drawing

  @Test func theBrushLandsOnTheRotatedPicture() {
    let bitmap = MaskBitmap(width: 100, height: 100)
    let crop = CGRect(x: 0, y: 0, width: 100, height: 100)
    let p = bitmap.point(
      forViewPoint: CGPoint(x: 0, y: 0), viewSize: CGSize(width: 100, height: 100), crop: crop, imageWidth: 100,
      rotation: 90)
    #expect(abs(p.x - 0) < 0.001 && abs(p.y - 100) < 0.001)
  }
}

/// The wheel and the pinch on the canvas: the zoom of the slider, with the point under the cursor kept still.
struct CanvasZoomTests {
  @Test func zoomingAtTheCentreKeepsTheCentre() {
    let framing = FramingMath.zoomed(
      Framing(), by: 2, atCanvasFraction: CGPoint(x: 0.5, y: 0.5), imageWidth: 200, imageHeight: 100,
      canvasWidth: 100, canvasHeight: 100)
    #expect(abs(framing.zoom - 50) < 0.001 && abs(framing.offsetX) < 0.001 && abs(framing.offsetY) < 0.001)
  }

  @Test func zoomingAtACornerKeepsThePointUnderTheCursor() {
    let framing = FramingMath.zoomed(
      Framing(), by: 2, atCanvasFraction: CGPoint(x: 0, y: 0), imageWidth: 200, imageHeight: 100, canvasWidth: 100,
      canvasHeight: 100)
    let crop = FramingMath.cropRect(
      imageWidth: 200, imageHeight: 100, canvasWidth: 100, canvasHeight: 100, framing: framing)
    #expect(abs(crop.minX - 50) < 0.001 && abs(crop.minY) < 0.001 && abs(crop.width - 50) < 0.001)
  }

  @Test func theSliderRangeIsTheLimitInBothDirections() {
    let out = FramingMath.zoomed(
      Framing(zoom: -90), by: 0.01, atCanvasFraction: CGPoint(x: 0.5, y: 0.5), imageWidth: 200, imageHeight: 100,
      canvasWidth: 100, canvasHeight: 100)
    #expect(out.zoom == -100)
    let into = FramingMath.zoomed(
      Framing(zoom: 90), by: 100, atCanvasFraction: CGPoint(x: 0.5, y: 0.5), imageWidth: 200, imageHeight: 100,
      canvasWidth: 100, canvasHeight: 100)
    #expect(into.zoom == 100)
  }

  @Test func zoomingOutPastTheWholeImageIsAllowed() {
    // 200×100 in a 100×100 canvas: the whole image fits at about −50.
    let out = FramingMath.zoomed(
      Framing(zoom: -50), by: 0.7, atCanvasFraction: CGPoint(x: 0.5, y: 0.5), imageWidth: 200, imageHeight: 100,
      canvasWidth: 100, canvasHeight: 100)
    #expect(out.zoom < -50)
  }

  @Test func theRotationIsKept() {
    let out = FramingMath.zoomed(
      Framing(rotation: 30), by: 1.5, atCanvasFraction: CGPoint(x: 0.2, y: 0.8), imageWidth: 200, imageHeight: 100,
      canvasWidth: 100, canvasHeight: 100)
    #expect(out.rotation == 30)
  }
}

/// A drawing made on the framed picture goes back to the start image's own coordinates.
struct UnframeTests {
  func halves() -> CGImage {  // 100×100, left half red, right half blue
    let context = CGContext(
      data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
    return context.makeImage()!
  }

  func color(_ bitmap: PaintBitmap, _ x: Int, _ y: Int) -> [Int] {
    let base = (y * bitmap.width + x) * 4
    return (0..<4).map { Int(bitmap.pixels[base + $0]) }
  }

  @Test(arguments: [
    Framing(), Framing(zoom: 30, rotation: 90), Framing(zoom: 30, offsetX: 0.2, rotation: -90),
    Framing(zoom: -30, rotation: 180),
  ])
  func aDrawingOnTheFramedPictureLandsWhereItWasDrawn(framing: Framing) throws {
    let framed = try #require(InputComposer.frame(halves(), toWidth: 100, height: 100, framing: framing))
    let back = try #require(
      InputComposer.unframe(
        framed, canvasWidth: 100, canvasHeight: 100, framing: framing, imageWidth: 100, imageHeight: 100,
        toWidth: 100, height: 100))
    // Where both sides see the same thing: the left half red, the right half blue.
    let left = color(back, 30, 50)
    let right = color(back, 70, 50)
    #expect(left[0] > 240 && left[2] < 15 && left[3] > 240, "\(left)")
    #expect(right[2] > 240 && right[0] < 15 && right[3] > 240, "\(right)")
  }

  @Test func whatTheCanvasDoesNotShowStaysTransparent() throws {
    let framing = Framing(zoom: 100)  // 4× in: only the middle quarter of the picture is in the canvas
    let framed = try #require(InputComposer.frame(halves(), toWidth: 100, height: 100, framing: framing))
    let back = try #require(
      InputComposer.unframe(
        framed, canvasWidth: 100, canvasHeight: 100, framing: framing, imageWidth: 100, imageHeight: 100,
        toWidth: 100, height: 100))
    #expect(color(back, 5, 5)[3] == 0)
    #expect(color(back, 55, 50)[3] > 240)
  }
}
