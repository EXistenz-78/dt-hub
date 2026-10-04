import CoreGraphics
import Foundation
import ImageIO
import HubKit
import Testing
import UniformTypeIdentifiers

@testable import HubCore

struct PipelineInputsTests {
  let folder: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  func solid(_ red: Double, _ green: Double, _ blue: Double, side: Int = 64) -> CGImage {
    let context = CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
  }

  func write(_ image: CGImage, as name: String) -> PluginImageRef {
    let url = folder.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return PluginImageRef(name: name, path: url.path)
  }

  func pixel(_ image: CGImage) -> [Int] {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
    return bytes.map(Int.init)
  }

  func base() -> GenerationInputs {
    GenerationInputs(
      image: solid(0, 1, 0), hints: [GenerationHint(imageData: Data([1]))], mask: solid(1, 1, 1), enableInpainting: true)
  }

  func run(_ step: PipelineStep, previous: CGImage? = nil, usesMoodboard: Bool = true) -> GenerationInputs {
    PipelineInputs.inputs(
      for: step, base: base(), previousOutput: previous, canvasWidth: 128, canvasHeight: 64, usesMoodboard: usesMoodboard)
  }

  @Test func aPassThatAsksForNothingKeepsTheTabsInputs() {
    let result = run(PipelineStep())
    #expect(result.image?.width == 64)
    #expect(result.mask != nil)
    #expect(result.hints.count == 1 && result.enableInpainting)
  }

  @Test func thePreviousOutputBecomesTheStartImageFramedToTheCanvasWithoutTheMask() throws {
    let result = run(PipelineStep(useOutputAsStart: true), previous: solid(1, 0, 0))
    let image = try #require(result.image)
    #expect(image.width == 128 && image.height == 64)
    #expect(pixel(image)[0] > 250)
    #expect(result.mask == nil)
  }

  @Test func withoutAPreviousOutputTheTabsImageStays() {
    let result = run(PipelineStep(useOutputAsStart: true), previous: nil)
    #expect(result.image?.width == 64 && result.mask != nil)
  }

  @Test func aPassCanNameItsOwnStartImage() throws {
    let blue = write(solid(0, 0, 1), as: "blue.png")
    let result = run(PipelineStep(startImage: blue), previous: solid(1, 0, 0))
    #expect(try #require(result.image).width == 128)
    #expect(pixel(try #require(result.image))[2] > 250)
    #expect(result.mask == nil)
  }

  @Test func thePassMoodboardReplacesTheTabsAndAnUnreadablePictureIsLeftOut() {
    let sphere = write(solid(0.5, 0.5, 0.5), as: "sphere.png")
    let result = run(PipelineStep(moodboard: [sphere, PluginImageRef(name: "gone", path: folder.appendingPathComponent("gone.png").path)]))
    #expect(result.hints.count == 1)
    #expect(result.hints.first?.imageData != Data([1]))
    #expect(run(PipelineStep(moodboard: [])).hints.isEmpty)
  }

  @Test func aModelThatDoesNotReadTheMoodboardGetsNone() {
    let sphere = write(solid(0.5, 0.5, 0.5), as: "sphere.png")
    #expect(run(PipelineStep(moodboard: [sphere]), usesMoodboard: false).hints.isEmpty)
  }

  @Test func aMoodboardPictureIsReducedToTheLongSideOf1024() throws {
    let big = write(solid(0.2, 0.2, 0.2, side: 2000), as: "big.png")
    let hint = try #require(PluginImages.hint(big))
    let source = try #require(CGImageSourceCreateWithData(hint.imageData as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(max(image.width, image.height) == 1024)
  }
}
