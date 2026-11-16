import CoreGraphics
import HubKit
import Testing

@testable import HubCore

struct LocalEditViewMathTests {
  @Test func theViewsCentreIsTheImagesCentre() {
    let view = LocalEditViewMath(imageWidth: 4000, imageHeight: 3000, viewSize: CGSize(width: 400, height: 300))
    #expect(view.pixel(at: CGPoint(x: 200, y: 150)) == CGPoint(x: 2000, y: 1500))
  }

  @Test func aRectangleOnALetterboxedPreviewMapsToThePixelsUnderIt() {
    // A 2000 × 1000 image in a 400 × 400 view: 400 × 200, with 100 points above and below.
    let view = LocalEditViewMath(imageWidth: 2000, imageHeight: 1000, viewSize: CGSize(width: 400, height: 400))
    #expect(view.imageFrame == CGRect(x: 0, y: 100, width: 400, height: 200))
    let drawn = view.pixelRect(from: CGPoint(x: 40, y: 120), to: CGPoint(x: 140, y: 220))
    #expect(drawn == CGRect(x: 200, y: 100, width: 500, height: 500))
    #expect(view.viewRect(of: PixelRect(x: 200, y: 100, width: 512, height: 512)) == CGRect(
      x: 40, y: 120, width: 102.4, height: 102.4))
  }

  @Test func pointsOutsideThePictureStopAtItsEdge() {
    let view = LocalEditViewMath(imageWidth: 2000, imageHeight: 1000, viewSize: CGSize(width: 400, height: 400))
    #expect(view.pixel(at: CGPoint(x: -30, y: 10)) == CGPoint(x: 0, y: 0))
    #expect(view.pixel(at: CGPoint(x: 900, y: 390)) == CGPoint(x: 2000, y: 1000))
  }

  @Test func theCropOfAReducedPreviewFollowsTheScale() {
    #expect(
      LocalEditViewMath.scaled(
        PixelRect(x: 1000, y: 500, width: 1024, height: 512), fromWidth: 4000, fromHeight: 3000, toWidth: 1400,
        toHeight: 1050) == PixelRect(x: 350, y: 175, width: 358, height: 179))
  }
}
