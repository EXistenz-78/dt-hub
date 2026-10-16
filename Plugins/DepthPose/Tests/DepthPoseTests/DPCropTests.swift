import CoreGraphics
import Testing

@testable import DepthPose

@Suite("DPCrop")
struct DPCropTests {
  private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-3) -> Bool { abs(a - b) <= tolerance }

  /// The reference values come from rtmlib's `bbox_xyxy2cs` and `get_warp_matrix` (padding 1.25, output 288×384).
  @Test func theThreeReferenceBoxes() {
    let cases: [(CGRect, (Double, Double), (Double, Double), Double, (Double, Double))] = [
      (CGRect(x: 30, y: 45, width: 95, height: 273), (77.5, 181.5), (255.9375, 341.25), 1.125275, (56.791209, -12.237363)),
      (CGRect(x: 0, y: 0, width: 320, height: 320), (160, 160), (400, 533.3333), 0.72, (28.8, 76.8)),
      (CGRect(x: 10, y: 20, width: 200, height: 100), (110, 70), (250, 333.3334), 1.152, (17.28, 111.36)),
    ]
    for (box, center, scale, factor, translation) in cases {
      let crop = DPCrop(box: box)
      #expect(near(crop.center.x, center.0) && near(crop.center.y, center.1), "\(box)")
      #expect(near(crop.scale.width, scale.0) && near(crop.scale.height, scale.1), "\(box)")
      #expect(near(crop.factor, factor, 1e-5), "\(box)")
      #expect(near(crop.translation.x, translation.0, 1e-3) && near(crop.translation.y, translation.1, 1e-3), "\(box)")
    }
  }

  @Test func theAreaAlwaysHasTheRatioOfTheModelInput() {
    for box in [CGRect(x: 0, y: 0, width: 400, height: 40), CGRect(x: 0, y: 0, width: 40, height: 400), CGRect(x: 5, y: 5, width: 100, height: 133)] {
      let crop = DPCrop(box: box)
      #expect(near(crop.scale.width / crop.scale.height, 0.75, 1e-6), "\(box)")
    }
  }

  @Test func theCentreBinIsTheCentreOfTheBoxAndBinZeroTheTopLeftOfTheArea() {
    let crop = DPCrop(box: CGRect(x: 30, y: 45, width: 95, height: 273))
    let centre = crop.imagePoint(binX: 288, binY: 384)
    #expect(near(centre.x, 77.5) && near(centre.y, 181.5))
    let corner = crop.imagePoint(binX: 0, binY: 0)
    #expect(near(corner.x, 77.5 - crop.scale.width / 2) && near(corner.y, 181.5 - crop.scale.height / 2))
    let far = crop.imagePoint(binX: 576, binY: 768)
    #expect(near(far.x, 77.5 + crop.scale.width / 2) && near(far.y, 181.5 + crop.scale.height / 2))
  }

  /// A black 320×320 picture with a white square of 10 pixels at its centre.
  private func squarePicture() -> CGImage {
    let context = CGContext(
      data: nil, width: 320, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 155, y: 155, width: 10, height: 10))
    return context.makeImage()!
  }

  @Test func theRenderHasTheModelSizeAndPutsAKnownPixelWhereExpected() throws {
    let crop = DPCrop(box: CGRect(x: 0, y: 0, width: 320, height: 320))
    let image = try #require(crop.render(squarePicture()))
    #expect(image.width == 288 && image.height == 384)
    #expect(Pictures.pixel(image, 144, 192)[0] > 200, "the centre of the crop is the centre of the picture: white")
    #expect(Pictures.pixel(image, 20, 100) == [0, 0, 0])
  }

  @Test func theRenderIsNotFlipped() throws {
    // A white square in the upper left of a black picture stays in the upper left of the crop.
    let context = CGContext(
      data: nil, width: 320, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 220, width: 100, height: 100))  // CoreGraphics: y up, so this is the top left
    let crop = DPCrop(box: CGRect(x: 0, y: 0, width: 320, height: 320))
    let image = try #require(crop.render(context.makeImage()!))
    // Picture (50, 50) from the top left -> crop (0.72·50 + 28.8, 0.72·50 + 76.8) = (64.8, 112.8)
    #expect(Pictures.pixel(image, 65, 113)[0] > 200)
    // Picture (50, 270) from the top left -> crop (64.8, 271.2): black
    #expect(Pictures.pixel(image, 65, 271)[0] < 50)
  }

  @Test func theRenderIsBlackWhereTheBoxLeavesThePicture() throws {
    let white = Pictures.image(width: 100, height: 100, red: 255)
    let image = try #require(DPCrop(box: CGRect(x: 0, y: 0, width: 100, height: 100)).render(white))
    #expect(Pictures.pixel(image, 0, 0) == [0, 0, 0], "outside the picture")
    #expect(Pictures.pixel(image, 144, 192)[0] > 200, "inside the picture")
  }

  @Test func aZeroSizedBoxDoesNotCrash() {
    let crop = DPCrop(box: .zero)
    #expect(crop.scale.width > 0 && crop.scale.height > 0 && crop.factor.isFinite)
    let image = crop.render(Pictures.image(width: 50, height: 50))
    #expect(image?.width == 288 && image?.height == 384)
  }
}
