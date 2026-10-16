import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import DepthPose

/// Pictures made on the spot for the tests.
enum Pictures {
  static func image(width: Int, height: Int, alpha: Bool = false, red: UInt8 = 200) -> CGImage {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue)!
    if !alpha {
      context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [CGFloat(red) / 255, 0, 0, 1])!)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return context.makeImage()!
  }

  static func data(_ image: CGImage, type: UTType = .png, orientation: Int? = nil) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  /// The RGB of one pixel, row 0 at the top.
  static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let i = (y * image.width + x) * 4
    return [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])]
  }
}

@Suite("DPImage")
struct DPImageTests {
  @Test func aLargeImageIsReducedToTheLimit() throws {
    let image = try #require(DPImage.load(data: Pictures.data(Pictures.image(width: 4000, height: 3000))))
    #expect(image.width == 2048 && image.height == 1536)
  }

  @Test func aSmallImageIsKept() throws {
    let image = try #require(DPImage.load(data: Pictures.data(Pictures.image(width: 300, height: 200))))
    #expect(image.width == 300 && image.height == 200)
  }

  @Test func theExifOrientationIsApplied() throws {
    let data = Pictures.data(Pictures.image(width: 40, height: 20), type: .jpeg, orientation: 6)
    let image = try #require(DPImage.load(data: data))
    #expect(image.width == 20 && image.height == 40)
  }

  @Test func aTransparentImageGetsABlackBackground() throws {
    let image = try #require(DPImage.load(data: Pictures.data(Pictures.image(width: 10, height: 10, alpha: true))))
    #expect(Pictures.pixel(image, 5, 5) == [0, 0, 0])
  }

  @Test func theResultIsAlwaysEightBitRGB() throws {
    let image = try #require(DPImage.load(data: Pictures.data(Pictures.image(width: 30, height: 30))))
    #expect(image.bitsPerComponent == 8 && image.bitsPerPixel == 32)
  }

  @Test func garbageReturnsNil() {
    #expect(DPImage.load(data: Data("not a picture".utf8)) == nil)
    #expect(DPImage.load(data: Data()) == nil)
  }

  @Test func aFileIsReadLikeItsData() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dp-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try Pictures.data(Pictures.image(width: 64, height: 32)).write(to: url)
    let image = try #require(DPImage.load(file: url))
    #expect(image.width == 64 && image.height == 32)
    #expect(DPImage.load(file: url.appendingPathExtension("missing")) == nil)
  }
}
