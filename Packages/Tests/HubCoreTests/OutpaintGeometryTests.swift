import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

struct OutpaintGeometryTests {
  func crop(_ framing: Framing, image: (Int, Int) = (1000, 1000), canvas: (Int, Int) = (1200, 900)) -> CGRect {
    FramingMath.cropRect(
      imageWidth: image.0, imageHeight: image.1, canvasWidth: canvas.0, canvasHeight: canvas.1, framing: framing)
  }

  @Test func theFactorIsExponentialAndLimited() {
    #expect(FramingMath.factor(zoom: 0) == 1)
    #expect(FramingMath.factor(zoom: 100) == 4)
    #expect(FramingMath.factor(zoom: -100) == 0.25)
    #expect(FramingMath.factor(zoom: 900) == 4)
    #expect(FramingMath.factor(zoom: -900) == 0.25)
  }

  @Test func aZoomOfZeroIsTheFill() {
    #expect(crop(Framing()) == CGRect(x: 0, y: 125, width: 1000, height: 750))
  }

  @Test func aPositiveZoomShrinksTheWindowAroundTheCentre() {
    #expect(crop(Framing(zoom: 100)) == CGRect(x: 375, y: 406.25, width: 250, height: 187.5))
  }

  @Test func aNegativeZoomMakesTheWindowLargerThanTheImage() {
    #expect(crop(Framing(zoom: -100)) == CGRect(x: -1500, y: -1000, width: 4000, height: 3000))
  }

  @Test func theOffsetPutsTheImageAgainstTheStartOrTheEndOfTheCanvas() {
    #expect(crop(Framing(zoom: -100, offsetX: -1, offsetY: -1)) == CGRect(x: 0, y: 0, width: 4000, height: 3000))
    #expect(crop(Framing(zoom: -100, offsetX: 1, offsetY: 1)) == CGRect(x: -3000, y: -2000, width: 4000, height: 3000))
  }

  @Test func theZoomWhereTheWholeImageFits() {
    let contain = FramingMath.zoomContain(imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900)
    #expect(abs(contain + 20.752) < 0.01)
    #expect(FramingMath.zoomContain(imageWidth: 400, imageHeight: 300, canvasWidth: 800, canvasHeight: 600) == 0)
    let margins = FramingMath.margins(
      imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, framing: Framing(zoom: contain))
    #expect(abs(margins.left - 150) < 0.01 && abs(margins.right - 150) < 0.01)
    #expect(margins.top < 0.01 && margins.bottom < 0.01)
    let loss = FramingMath.loss(
      imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, zoom: contain)
    #expect(loss.axis == nil)
  }

  @Test func theFillAndAPositiveZoomHaveNoMargins() {
    for zoom in [0.0, 30, 100] {
      let margins = FramingMath.margins(
        imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, framing: Framing(zoom: zoom))
      #expect(margins.isEmpty)
    }
    let same = FramingMath.margins(
      imageWidth: 400, imageHeight: 300, canvasWidth: 800, canvasHeight: 600, framing: Framing())
    #expect(same.isEmpty)
  }

  @Test func marginsAreMeasuredInCanvasPixelsOnEachSide() {
    // 100×100 in a 200×100 canvas at −50: the image is 100 wide, centred; against the start it has no left margin.
    let centred = FramingMath.margins(
      imageWidth: 100, imageHeight: 100, canvasWidth: 200, canvasHeight: 100, framing: Framing(zoom: -50))
    #expect(abs(centred.left - 50) < 0.01 && abs(centred.right - 50) < 0.01)
    let atStart = FramingMath.margins(
      imageWidth: 100, imageHeight: 100, canvasWidth: 200, canvasHeight: 100, framing: Framing(zoom: -50, offsetX: -1))
    #expect(atStart.left < 0.01 && abs(atStart.right - 100) < 0.01)
  }

  @Test func theShareOfTheImageThatIsUsed() {
    func share(_ zoom: Double) -> Double {
      FramingMath.usedShare(
        imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, framing: Framing(zoom: zoom))
    }
    #expect(abs(share(0) - 0.75) < 0.0001)
    #expect(abs(share(100) - 0.046875) < 0.0001)
    #expect(share(-100) == 1)
  }
}
