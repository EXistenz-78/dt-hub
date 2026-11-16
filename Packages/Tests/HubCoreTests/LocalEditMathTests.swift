import CoreGraphics
import HubKit
import Testing

@testable import HubCore

struct LocalEditMathTests {
  @Test func aSmallBoxGrowsTo512AroundItsCentre() {
    #expect(
      LocalEditMath.snapped(
        CGRect(x: 1000, y: 1000, width: 100, height: 50), imageWidth: 4000, imageHeight: 3000)
        == PixelRect(x: 794, y: 769, width: 512, height: 512))
  }

  @Test func sidesGoUpToTheNextMultipleOf64() {
    #expect(
      LocalEditMath.snapped(
        CGRect(x: 0, y: 0, width: 700, height: 600), imageWidth: 4000, imageHeight: 3000)
        == PixelRect(x: 0, y: 0, width: 704, height: 640))
  }

  @Test func aBoxAgainstTheEdgeStaysInside() {
    #expect(
      LocalEditMath.snapped(
        CGRect(x: 3700, y: 2800, width: 300, height: 200), imageWidth: 4000, imageHeight: 3000)
        == PixelRect(x: 3488, y: 2488, width: 512, height: 512))
  }

  @Test func anImageNotAMultipleOf64KeepsTheCropInside() {
    #expect(
      LocalEditMath.snapped(
        CGRect(x: 0, y: 0, width: 1000, height: 1000), imageWidth: 1000, imageHeight: 700)
        == PixelRect(x: 20, y: 30, width: 960, height: 640))
  }

  @Test func nothingUnder512AndNothingOutside() {
    #expect(
      LocalEditMath.snapped(
        CGRect(x: 0, y: 0, width: 300, height: 300), imageWidth: 500, imageHeight: 2000) == nil)
    #expect(
      LocalEditMath.snapped(
        CGRect(x: 5000, y: 0, width: 10, height: 10), imageWidth: 4000, imageHeight: 3000) == nil)
  }

  @Test func theLongestSideStopsAt4096() {
    #expect(
      LocalEditMath.snapped(
        CGRect(x: 0, y: 0, width: 6000, height: 1000), imageWidth: 8000, imageHeight: 2000)?.width
        == 4096)
  }

  @Test func theFeatherIs3PercentOfTheShortSideAtLeast8() {
    #expect(LocalEditMath.featherWidth(for: PixelRect(x: 0, y: 0, width: 1024, height: 512)) == 15)
    #expect(LocalEditMath.featherWidth(for: PixelRect(x: 0, y: 0, width: 512, height: 256)) == 8)
  }
}
