import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HubCore

struct GuidedPassInputsTests {
  private let folder: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("GuidedPassInputs-\(UUID())")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  /// A PNG of `width` × `height` pixels, grey or RGB, with `value(x)` as the grey level (or the red channel) of column x.
  private func png(_ name: String, width: Int, height: Int, gray: Bool, value: (Int) -> UInt8) -> PluginImageRef {
    let channels = gray ? 1 : 4
    var bytes = [UInt8](repeating: 255, count: width * height * channels)
    for y in 0..<height {
      for x in 0..<width {
        let base = (y * width + x) * channels
        bytes[base] = value(x)
        if !gray { (1..<3).forEach { bytes[base + $0] = 0 } }
      }
    }
    let image = CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * channels, bytesPerRow: width * channels,
      space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let url = folder.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return PluginImageRef(name: name, path: url.path)
  }

  /// The alpha of the pixel (x, y).
  private func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return pixel[3]
  }

  private func step(start: PluginImageRef?, mask: PluginImageRef? = nil, size: PipelineSize) -> PipelineStep {
    PipelineStep(startImage: start, mask: mask, size: size)
  }

  @Test func usesTheStepImageAndNoMaskWhenThePassHasNone() throws {
    let tile = png("tile.png", width: 8, height: 4, gray: false) { _ in 200 }
    let result = GuidedPassInputs.inputs(for: step(start: tile, size: PipelineSize(width: 8, height: 4)), enableInpainting: false)
    let inputs = try result.get()
    #expect(inputs.image?.width == 8 && inputs.image?.height == 4)
    #expect(inputs.mask == nil)
    #expect(inputs.hints.isEmpty)
    #expect(!inputs.enableInpainting)
  }

  @Test func convertsTheMaskPNGToTheGenerationConvention() throws {
    let tile = png("tile.png", width: 4, height: 4, gray: false) { _ in 10 }
    let mask = png("mask.png", width: 4, height: 4, gray: true) { $0 >= 2 ? 255 : 0 }
    let inputs = try GuidedPassInputs.inputs(
      for: step(start: tile, mask: mask, size: PipelineSize(width: 4, height: 4)), enableInpainting: true
    ).get()
    let result = try #require(inputs.mask)
    #expect(result.width == 4 && result.height == 4)
    #expect(alpha(result, 3, 1) == 0, "painted pixels are regenerated: transparent")
    #expect(alpha(result, 0, 1) == 255, "the rest is kept: opaque")
    #expect(inputs.enableInpainting)
  }

  @Test func rejectsAMaskOfAnotherSize() {
    let tile = png("tile.png", width: 8, height: 8, gray: false) { _ in 10 }
    let mask = png("mask.png", width: 4, height: 4, gray: true) { _ in 255 }
    let result = GuidedPassInputs.inputs(
      for: step(start: tile, mask: mask, size: PipelineSize(width: 8, height: 8)), enableInpainting: false)
    #expect(result.failure == .maskSize(expected: PipelineSize(width: 8, height: 8), got: PipelineSize(width: 4, height: 4)))
  }

  @Test func rejectsAnImageOfAnotherSize() {
    let tile = png("tile.png", width: 8, height: 8, gray: false) { _ in 10 }
    let result = GuidedPassInputs.inputs(for: step(start: tile, size: PipelineSize(width: 16, height: 8)), enableInpainting: false)
    #expect(result.failure == .imageSize(expected: PipelineSize(width: 16, height: 8), got: PipelineSize(width: 8, height: 8)))
  }

  @Test func rejectsAnUnreadableImageOrMask() {
    let missing = PluginImageRef(name: "x", path: folder.appendingPathComponent("nope.png").path)
    #expect(
      GuidedPassInputs.inputs(for: step(start: missing, size: PipelineSize(width: 8, height: 8)), enableInpainting: false)
        .failure == .imageUnreadable)
    let tile = png("tile.png", width: 8, height: 8, gray: false) { _ in 10 }
    #expect(
      GuidedPassInputs.inputs(
        for: step(start: tile, mask: missing, size: PipelineSize(width: 8, height: 8)), enableInpainting: false
      ).failure == .maskUnreadable)
  }

  @Test func aPassStartsFromTheTabWithoutItsLoRAsAndWithOneImage() {
    var tab = GenerationFields(prompt: "tab prompt")
    tab.parameters.loras = [LoRASelection(file: "user.ckpt", weight: 0.5)]
    tab.parameters.batchSize = 4
    tab.parameters.batchCount = 3
    tab.parameters.steps = 20
    let base = GuidedPassInputs.baseFields(from: tab, size: PipelineSize(width: 512, height: 768))
    #expect(base.parameters.loras.isEmpty, "the tab's LoRAs are not in a tile")
    #expect(base.parameters.batchSize == 1 && base.parameters.batchCount == 1, "one picture per tile")
    #expect(base.parameters.width == 512 && base.parameters.height == 768)
    #expect(base.parameters.steps == 20 && base.prompt == "tab prompt", "the rest stays the tab's")
  }

  @Test func aStepWithoutAStartImageOrSizeFails() {
    #expect(GuidedPassInputs.inputs(for: PipelineStep(), enableInpainting: false).failure == .imageUnreadable)
  }

  // MARK: a pass with no start image and a Moodboard of its own

  @Test func aPassWithoutAStartImageStartsFromAnEmptyCanvasOfItsSize() throws {
    let inputs = try GuidedPassInputs.inputs(
      for: PipelineStep(size: PipelineSize(width: 2048, height: 1024)), enableInpainting: false, usesMoodboard: true
    ).get()
    #expect(inputs.image == nil, "no start image: the model draws on an empty canvas")
    #expect(inputs.mask == nil)
    #expect(inputs.hints.isEmpty)
  }

  @Test func theMoodboardOfThePassBecomesTheHintsInTheOrderGiven() throws {
    let first = png("ref1.png", width: 8, height: 8, gray: false) { _ in 30 }
    let second = png("ref2.png", width: 8, height: 8, gray: false) { _ in 220 }
    let step = PipelineStep(moodboard: [first, second], size: PipelineSize(width: 2048, height: 1024))
    let inputs = try GuidedPassInputs.inputs(for: step, enableInpainting: false, usesMoodboard: true).get()
    let expected = try [first, second].map { try #require(PluginImages.hint($0)).imageData }
    #expect(inputs.hints.map(\.imageData) == expected)
    #expect(inputs.image == nil)
  }

  @Test func theMoodboardIsLeftOutForAModelThatDoesNotReadIt() throws {
    let reference = png("ref.png", width: 8, height: 8, gray: false) { _ in 30 }
    let step = PipelineStep(moodboard: [reference], size: PipelineSize(width: 2048, height: 1024))
    let inputs = try GuidedPassInputs.inputs(for: step, enableInpainting: false, usesMoodboard: false).get()
    #expect(inputs.hints.isEmpty)
  }

  @Test func aStartImageAndAMoodboardCanGoTogether() throws {
    let tile = png("tile.png", width: 8, height: 4, gray: false) { _ in 200 }
    let reference = png("ref.png", width: 8, height: 8, gray: false) { _ in 30 }
    let step = PipelineStep(moodboard: [reference], startImage: tile, size: PipelineSize(width: 8, height: 4))
    let inputs = try GuidedPassInputs.inputs(for: step, enableInpainting: false, usesMoodboard: true).get()
    #expect(inputs.image?.width == 8 && inputs.hints.count == 1)
  }

  @Test func aMaskNeedsAStartImage() {
    let mask = png("mask.png", width: 8, height: 8, gray: true) { _ in 255 }
    let step = PipelineStep(mask: mask, size: PipelineSize(width: 8, height: 8))
    #expect(
      GuidedPassInputs.inputs(for: step, enableInpainting: false, usesMoodboard: true).failure == .maskWithoutImage)
  }

  /// The pass the Pano 360 F3 plug-in answers first: it goes through the app's parser, then through `GuidedPassInputs`, as a real run does.
  @Test func aPanoramaPassAnswerParsesAndGivesAMoodboardOnlyInput() throws {
    let ref = png("ref.png", width: 8, height: 8, gray: false) { _ in 30 }
    let json =
      #"{"title":"Panorama","preset":"PANO F3","moodboard":[{"path":"\#(ref.path)","name":"ref.png"}],"size":{"width":2048,"height":1024},"fields":{"prompt":"starting from <image 1>","highRes":true,"randomSeed":true},"loras":[{"file":"f3_360_lora_f16.ckpt","weight":1.0,"mode":0,"trigger":"create a 360 hdr"}]}"#
    guard case .pass(let step) = SessionAnswer.parse(Data(json.utf8), tileLimit: 8192) else {
      Issue.record("the app's parser refused the pass")
      return
    }
    let inputs = try GuidedPassInputs.inputs(for: step, enableInpainting: false, usesMoodboard: true).get()
    #expect(inputs.image == nil && inputs.hints.count == 1)
  }

  @Test func aStartImagePassWithoutTheNewArgumentStillRunsAsBefore() throws {
    let tile = png("tile.png", width: 8, height: 4, gray: false) { _ in 200 }
    let inputs = try GuidedPassInputs.inputs(
      for: step(start: tile, size: PipelineSize(width: 8, height: 4)), enableInpainting: false
    ).get()
    #expect(inputs.image != nil && inputs.hints.isEmpty, "Tiled Upscale answers keep working untouched")
  }
}

extension Result {
  fileprivate var failure: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }
}
