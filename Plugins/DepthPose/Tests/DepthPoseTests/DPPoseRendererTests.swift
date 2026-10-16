import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import DepthPose

@Suite("DPPoseRenderer")
struct DPPoseRendererTests {
  private func point(_ x: Double, _ y: Double, _ confidence: Double = 1) -> DPPoint {
    DPPoint(x: x, y: y, confidence: confidence)
  }

  /// A person on a 200×200 picture: neck at pixel (100,100), nose above it, shoulders to the left and right.
  private var person: DPPerson {
    [
      .nose: point(0.5, 0.2), .neck: point(0.5, 0.5), .rightShoulder: point(0.25, 0.5), .leftShoulder: point(0.75, 0.5),
      .rightElbow: point(0.25, 0.8),
    ]
  }

  /// The RGB of one pixel, row 0 at the top.
  private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    data.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let i = (y * image.width + x) * 4
    return [Int(data[i]), Int(data[i + 1]), Int(data[i + 2])]
  }

  private func near(_ a: [Int], _ b: [Int], _ tolerance: Int = 3) -> Bool {
    zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
  }

  private func colour(_ index: Int, scale: Double = 1) -> [Int] {
    let c = DPPoseRenderer.colors[index]
    return [Int(Double(c.0) * scale), Int(Double(c.1) * scale), Int(Double(c.2) * scale)]
  }

  @Test func theTableHasEighteenColours() {
    #expect(DPPoseRenderer.colors.count == 18)
    #expect(DPPoseRenderer.colors[0] == (255, 0, 0) && DPPoseRenderer.colors[17] == (255, 0, 85))
  }

  @Test func backgroundIsBlack() throws {
    let image = try #require(DPPoseRenderer.render([person], width: 200, height: 200))
    #expect(pixel(image, 0, 0) == [0, 0, 0])
    #expect(image.width == 200 && image.height == 200)
  }

  @Test func aJointIsTheFullColourOfItsIndex() throws {
    let image = try #require(DPPoseRenderer.render([person], width: 200, height: 200))
    #expect(near(pixel(image, 100, 100), colour(1)))  // neck
  }

  @Test func aBoneIsSixtyPercentOfItsColour() throws {
    let image = try #require(DPPoseRenderer.render([person], width: 200, height: 200))
    // Bone 0 is neck → right shoulder: its midpoint is pixel (75,100).
    #expect(near(pixel(image, 75, 100), colour(0, scale: 0.6)))
    // Bone 12 is neck → nose: its midpoint is pixel (100,60).
    #expect(near(pixel(image, 100, 70), colour(12, scale: 0.6)))
  }

  @Test func jointsAreDrawnOverTheBones() throws {
    let image = try #require(DPPoseRenderer.render([person], width: 200, height: 200))
    // Two bones start at the neck; next to it the joint wins.
    #expect(near(pixel(image, 101, 100), colour(1)))
  }

  @Test func twoPeopleAreBothDrawn() throws {
    let other: DPPerson = [.neck: point(0.1, 0.9), .rightShoulder: point(0.05, 0.9)]
    let image = try #require(DPPoseRenderer.render([person, other], width: 200, height: 200))
    #expect(near(pixel(image, 100, 100), colour(1)))
    #expect(near(pixel(image, 20, 180), colour(1)))
  }

  @Test func aBoneWithAMissingEndIsNotDrawn() throws {
    let weak: DPPerson = [
      .neck: point(0.5, 0.5), .rightShoulder: point(0.25, 0.5), .rightElbow: point(0.25, 0.9, 0.1),
    ]
    let image = try #require(DPPoseRenderer.render([weak], width: 200, height: 200))
    #expect(near(pixel(image, 75, 100), colour(0, scale: 0.6)))  // neck → shoulder is there
    #expect(pixel(image, 50, 140) == [0, 0, 0])  // shoulder → elbow is not
  }

  @Test func aPersonWithoutABoneIsNotDrawn() {
    #expect(DPPoseRenderer.render([[.nose: point(0.5, 0.5)]], width: 100, height: 100) == nil)
    #expect(DPPoseRenderer.render([], width: 100, height: 100) == nil)
  }

  @Test func thicknessIsProportionalWithAMinimum() {
    #expect(DPPoseRenderer.thickness(forLongSide: 100) == 3)
    #expect(DPPoseRenderer.thickness(forLongSide: 1700) == 10)
  }

  @Test func theBytesAreAPNGOfTheSameSize() throws {
    let image = try #require(DPPoseRenderer.render([person], width: 120, height: 80))
    let data = try #require(DPPoseRenderer.pngData(image))
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == "public.png")
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == 120 && decoded.height == 80)
  }
}
