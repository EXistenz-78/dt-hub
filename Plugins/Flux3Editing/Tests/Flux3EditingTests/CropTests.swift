import AppKit
import Foundation
import Testing

@testable import Flux3Editing

struct CropTests {
  private func picture(width: Int, height: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-\(UUID().uuidString).png")
    let rep = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-crops-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func theCropIsTheBoxOfThePicture() throws {
    let source = try picture(width: 400, height: 200)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    // y 0…500, x 0…500 of a 400×200 picture: 200 wide, 100 high.
    let path = try #require(EditCrops.crop(path: source.path, box: BBox(y0: 0, x0: 0, y1: 500, x1: 500), to: out, name: "el_1"))
    #expect(path.hasPrefix(out.path) && path.hasSuffix(".png"))
    #expect(ImageSizes.read(path: path) == CGSize(width: 200, height: 100))
  }

  @Test func aBigCropIsScaledDownToTheMaximumSide() throws {
    let source = try picture(width: 2000, height: 1000)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    let path = try #require(EditCrops.crop(path: source.path, box: BBox(y0: 0, x0: 0, y1: 1000, x1: 1000), to: out, name: "el_1", maxPixel: 500))
    let size = try #require(ImageSizes.read(path: path))
    #expect(max(size.width, size.height) == 500 && abs(size.width / size.height - 2) < 0.02)
  }

  @Test func anUnreadablePictureGivesNothing() {
    #expect(EditCrops.crop(path: "/nonexistent.png", box: BBox(y0: 0, x0: 0, y1: 500, x1: 500), to: folder(), name: "x") == nil)
  }

  @Test func theFileNameIsMadeSafe() throws {
    let source = try picture(width: 100, height: 100)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    let path = try #require(EditCrops.crop(path: source.path, box: BBox(y0: 0, x0: 0, y1: 500, x1: 500), to: out, name: "a/b<c>:d"))
    #expect(!(path as NSString).lastPathComponent.contains("/") && FileManager.default.fileExists(atPath: path))
  }
}
