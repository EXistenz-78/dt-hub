import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

struct MaskComposerTests {
  /// Alpha of the pixel at (x, y), counted from the top-left.
  func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return Int(bytes[3])
  }

  /// A 100×50 mask whose right half is painted.
  func rightHalf() -> MaskBitmap {
    var mask = MaskBitmap(width: 100, height: 50)
    for x in 50..<100 { mask.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 50), radius: 0.7, erase: false) }
    return mask
  }

  @Test func thePaintedHalfIsTransparentAndTheRestOpaque() throws {
    let canvas = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 200, height: 100, framing: Framing()))
    #expect(canvas.width == 200 && canvas.height == 100)
    #expect(alpha(canvas, 20, 50) == 255)
    #expect(alpha(canvas, 180, 50) == 0)
  }

  @Test func theMaskFollowsTheCut() throws {
    // A square canvas over a 2:1 image shows its left half (offset −1): the painted half is out.
    let left = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(offsetX: -1)))
    #expect(alpha(left, 10, 32) == 255 && alpha(left, 54, 32) == 255)
    // Offset 1 shows the right half: all of it is painted.
    let right = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(offsetX: 1)))
    #expect(alpha(right, 10, 32) == 0 && alpha(right, 54, 32) == 0)
  }

  @Test func theMaskIsScaledToTheCanvasWithAHardEdge() throws {
    let canvas = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 400, height: 200, framing: Framing()))
    var shades = Set<Int>()
    for x in stride(from: 0, to: 400, by: 7) { shades.insert(alpha(canvas, x, 100)) }
    #expect(shades == [0, 255])
  }

  @Test func paintAtTheTopOfTheMaskIsAtTheTopOfTheCanvas() throws {
    var mask = MaskBitmap(width: 100, height: 100)
    for x in 0..<100 { mask.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0.5), to: CGPoint(x: Double(x) + 0.5, y: 20.5), radius: 0.7, erase: false) }
    let canvas = try #require(InputComposer.mask(mask, imageWidth: 100, imageHeight: 100, toWidth: 100, height: 100, framing: Framing()))
    #expect(alpha(canvas, 50, 5) == 0)
    #expect(alpha(canvas, 50, 90) == 255)
  }

  @Test func theDrawingIsPutOverTheImageInTheSameCut() throws {
    // A 200×100 white image framed on a 100×100 canvas, the cut on its right half; a mark at the
    // left of the drawing is out of the cut, a mark at the right is in.
    let context = CGContext(
      data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
    let white = try #require(context.makeImage())
    var paint = PaintBitmap(width: 100, height: 50)
    paint.stroke(from: CGPoint(x: 10, y: 25), to: CGPoint(x: 10, y: 25), radius: 4, red: 255, green: 0, blue: 0)
    paint.stroke(from: CGPoint(x: 80, y: 25), to: CGPoint(x: 80, y: 25), radius: 4, red: 255, green: 0, blue: 0)
    let framed = try #require(
      InputComposer.frame(white, toWidth: 100, height: 100, framing: Framing(offsetX: 1), paint: paint))
    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int) {
      var bytes = [UInt8](repeating: 0, count: 4)
      let one = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      one.draw(framed, in: CGRect(x: -x, y: -(framed.height - 1 - y), width: framed.width, height: framed.height))
      return (Int(bytes[0]), Int(bytes[1]))
    }
    // The mark at 80/100 of the image width is at (160 − 100) / 100 = 0.6 of the canvas.
    #expect(pixel(60, 50).g < 40 && pixel(60, 50).r > 215)
    // Elsewhere the image stays white.
    #expect(pixel(20, 50).g > 240)
  }
}
