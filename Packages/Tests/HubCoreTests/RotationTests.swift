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
