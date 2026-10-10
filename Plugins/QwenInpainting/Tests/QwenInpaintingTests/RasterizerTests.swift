import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import QwenInpainting

@Suite("Rasterizer")
struct RasterizerTests {
  func box(_ color: MarkColor = .red, width: Double = 4) -> Mark {
    Mark(tool: .box, color: color, width: width, points: [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.75)])
  }

  func temp(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("qi-\(UUID().uuidString)").appendingPathComponent(name)
  }

  @Test func theBoxIsDrawnInPureRedAndTheInsideStaysTransparent() throws {
    let image = try #require(Rasterizer.paint([box()], size: CGSize(width: 200, height: 100)))
    #expect(image.width == 200 && image.height == 100)
    let edge = try #require(Rasterizer.pixel(image, x: 50, y: 50))
    #expect(edge.r == 255 && edge.g == 0 && edge.b == 0 && edge.a == 255)
    #expect(try #require(Rasterizer.pixel(image, x: 100, y: 50)).a == 0)
    #expect(try #require(Rasterizer.pixel(image, x: 2, y: 2)).a == 0)
  }

  @Test func theTopOfTheImageIsTheTopOfTheDrawing() throws {
    // A box in the upper left only: the top left corner has colour, the bottom left has not.
    let mark = Mark(tool: .box, color: .blue, width: 8, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.4)])
    let image = try #require(Rasterizer.paint([mark], size: CGSize(width: 100, height: 100)))
    #expect(try #require(Rasterizer.pixel(image, x: 10, y: 25)).a == 255)
    #expect(try #require(Rasterizer.pixel(image, x: 10, y: 75)).a == 0)
  }

  @Test func aPortraitImageGivesAPortraitDrawing() throws {
    let image = try #require(Rasterizer.paint([box()], size: CGSize(width: 768, height: 1344)))
    #expect(image.width == 768 && image.height == 1344)
  }

  @Test func marksAtTheLimitsAreDrawnWithoutProblems() throws {
    let mark = Mark(tool: .sketch, color: .red, points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)])
    let image = try #require(Rasterizer.paint([mark], size: CGSize(width: 50, height: 50)))
    #expect(try #require(Rasterizer.pixel(image, x: 25, y: 25)).a > 0)
  }

  @Test func theFusedPictureIsReducedAndKeepsTheMarks() throws {
    let white = try #require(solid(width: 3000, height: 1500, white: true))
    let drawing = try #require(Rasterizer.paint([box(width: 40)], size: CGSize(width: 3000, height: 1500)))
    let fused = try #require(Rasterizer.fused(start: white, paint: drawing, maxSide: 1536))
    #expect(max(fused.width, fused.height) == 1536 && fused.width == 1536 && fused.height == 768)
    let edge = try #require(Rasterizer.pixel(fused, x: 384, y: 384))
    #expect(edge.r == 255 && edge.g == 0 && edge.b == 0)
    #expect(try #require(Rasterizer.pixel(fused, x: 5, y: 5)).g == 255)  // white elsewhere
  }

  func solid(width: Int, height: Int, white: Bool) -> CGImage? {
    guard let c = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    c.setFillColor(red: white ? 1 : 0, green: white ? 1 : 0, blue: white ? 1 : 0, alpha: 1)
    c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return c.makeImage()
  }

  /// A JPEG 100×50 saved with the EXIF orientation `orientation`.
  func jpeg(orientation: Int) throws -> String {
    let url = temp("o.jpg")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let image = try #require(solid(width: 100, height: 50, white: true))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url.path
  }

  @Test func theExifOrientationIsAppliedToTheSizeAndToThePicture() throws {
    let path = try jpeg(orientation: 6)
    #expect(Rasterizer.imageSize(at: path) == CGSize(width: 50, height: 100))
    let upright = try #require(Rasterizer.orientedImage(at: path, maxSide: nil))
    #expect(upright.width == 50 && upright.height == 100)
    let plain = try jpeg(orientation: 1)
    #expect(Rasterizer.imageSize(at: plain) == CGSize(width: 100, height: 50))
    let small = try #require(Rasterizer.orientedImage(at: plain, maxSide: 50))
    #expect(max(small.width, small.height) == 50)
  }

  @Test func aPNGIsWrittenAndReadBack() throws {
    let image = try #require(Rasterizer.paint([box()], size: CGSize(width: 40, height: 20)))
    let url = temp("paint.png")
    try Rasterizer.writePNG(image, to: url)
    #expect(Rasterizer.imageSize(at: url.path) == CGSize(width: 40, height: 20))
  }
}
