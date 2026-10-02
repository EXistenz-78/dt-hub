import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

struct OutpaintComposerTests {
  /// A 100×100 image: red and blue halves, side by side (left red) or one over the other (top red).
  func halves(vertical: Bool) -> CGImage {
    let context = CGContext(
      data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(vertical ? CGRect(x: 0, y: 50, width: 100, height: 50) : CGRect(x: 0, y: 0, width: 50, height: 100))
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

  func isRed(_ pixel: [Int]) -> Bool { pixel[0] > 250 && pixel[2] < 5 }
  func isBlue(_ pixel: [Int]) -> Bool { pixel[2] > 250 && pixel[0] < 5 }

  @Test func theImageSitsInTheMiddleAndTheMarginsTakeTheColoursOfItsEdges() throws {
    let framed = try #require(
      InputComposer.frame(halves(vertical: false), toWidth: 200, height: 100, framing: Framing(zoom: -50)))
    #expect(isRed(sample(framed, 10, 50)))  // the left margin continues the red edge
    #expect(isRed(sample(framed, 70, 50)) && isBlue(sample(framed, 130, 50)))  // the image itself
    #expect(isBlue(sample(framed, 190, 50)))  // the right margin continues the blue edge
  }

  @Test func theMarginsAboveAndBelowAndTheCornersToo() throws {
    // 100×100 in a 100×200 canvas at −50: the image keeps its size and sits in the middle of the height.
    let framed = try #require(
      InputComposer.frame(halves(vertical: true), toWidth: 100, height: 200, framing: Framing(zoom: -50)))
    #expect(isRed(sample(framed, 50, 10)) && isRed(sample(framed, 5, 10)) && isRed(sample(framed, 95, 10)))
    #expect(isBlue(sample(framed, 50, 190)) && isBlue(sample(framed, 5, 190)) && isBlue(sample(framed, 95, 190)))
    #expect(isRed(sample(framed, 50, 80)) && isBlue(sample(framed, 50, 120)))
  }

  @Test func theOffsetMovesTheImageInTheCanvas() throws {
    let framed = try #require(
      InputComposer.frame(halves(vertical: false), toWidth: 200, height: 100, framing: Framing(zoom: -50, offsetX: -1)))
    #expect(isRed(sample(framed, 10, 50)) && isRed(sample(framed, 40, 50)))  // image against the start
    #expect(isBlue(sample(framed, 80, 50)) && isBlue(sample(framed, 190, 50)))
  }

  @Test func aPositiveZoomShowsAPartOfTheImageOnly() throws {
    let framed = try #require(
      InputComposer.frame(halves(vertical: false), toWidth: 64, height: 64, framing: Framing(zoom: 100)))
    // A quarter of the image around its centre: red on the left of the centre line, blue on the right.
    #expect(isRed(sample(framed, 2, 32)) && isBlue(sample(framed, 61, 32)))
  }

  @Test func theMarginsAreRegeneratedEvenWithoutAPaintedMask() throws {
    let mask = try #require(
      InputComposer.mask(nil, imageWidth: 100, imageHeight: 100, toWidth: 200, height: 100, framing: Framing(zoom: -50)))
    #expect(mask.width == 200 && mask.height == 100)
    #expect(sample(mask, 10, 50)[3] == 0)
    #expect(sample(mask, 100, 50)[3] == 255)
    #expect(sample(mask, 190, 50)[3] == 0)
  }

  @Test func thePaintedMaskGoesWithTheImageAndTheMarginsAddToIt() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    for x in 50..<100 {
      painted.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 100), radius: 0.7, erase: false)
    }
    let mask = try #require(
      InputComposer.mask(painted, imageWidth: 100, imageHeight: 100, toWidth: 200, height: 100, framing: Framing(zoom: -50)))
    #expect(sample(mask, 10, 50)[3] == 0)  // margin
    #expect(sample(mask, 70, 50)[3] == 255)  // image, kept
    #expect(sample(mask, 130, 50)[3] == 0)  // image, painted
  }

  @Test func thePaintedMaskFollowsTheImageWhenItIsMoved() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    for x in 50..<100 {
      painted.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 100), radius: 0.7, erase: false)
    }
    // Image against the start of the canvas: it covers x 0…100, the right half of it is painted.
    let mask = try #require(
      InputComposer.mask(
        painted, imageWidth: 100, imageHeight: 100, toWidth: 200, height: 100, framing: Framing(zoom: -50, offsetX: -1)))
    #expect(sample(mask, 20, 50)[3] == 255)  // image, kept
    #expect(sample(mask, 80, 50)[3] == 0)  // image, painted
    #expect(sample(mask, 150, 50)[3] == 0)  // margin
  }

  @Test func aPositiveZoomCutsTheMaskLikeTheImage() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    for x in 50..<100 {
      painted.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 100), radius: 0.7, erase: false)
    }
    // A quarter of the image around its centre: its left half is kept, its right half painted.
    let mask = try #require(
      InputComposer.mask(painted, imageWidth: 100, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(zoom: 100)))
    #expect(sample(mask, 5, 32)[3] == 255)
    #expect(sample(mask, 58, 32)[3] == 0)
  }

  @Test func withoutMarginsTheMaskIsAsBefore() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    painted.stroke(from: CGPoint(x: 80, y: 50), to: CGPoint(x: 80, y: 50), radius: 8, erase: false)
    let mask = try #require(
      InputComposer.mask(painted, imageWidth: 100, imageHeight: 100, toWidth: 100, height: 100, framing: Framing()))
    #expect(sample(mask, 80, 50)[3] == 0)
    #expect(sample(mask, 10, 10)[3] == 255)
    #expect(sample(mask, 0, 0)[3] == 255 && sample(mask, 99, 99)[3] == 255)
  }
}
