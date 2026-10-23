import Testing

@testable import PromptMasterMOSS

struct GeometryTests {
  /// Box dai pixel dall'angolo di una tela `w`×`h`, come lo salva il plug-in (frazioni).
  static func frac(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, in w: Double, _ h: Double) -> FracBox {
    FracBox(x0: x0 / w, y0: y0 / h, x1: x1 / w, y1: y1 / h)
  }
  let landscape = PixelSize(width: 1024, height: 640)

  @Test func umbrellaCentersExactly_notOffByOneFromFloatingPoint() {
    // 0.3·1024 non deve dare 306: 150/1024·1024 in virgola mobile sta sotto 150.
    let box = Self.frac(150, 30, 800, 330, in: 1024, 640)
    #expect(MossGeometry.centered(box, in: landscape) == [-290, -362, 10, 288])
  }

  @Test func fullCanvasBoxSpansAllTheCanvas() {
    #expect(MossGeometry.centered(FracBox(x0: 0, y0: 0, x1: 1, y1: 1), in: landscape) == [-320, -512, 320, 512])
  }

  @Test func theSameFractionsOnASquareCanvasAreRecomputed() {
    let box = Self.frac(150, 30, 800, 330, in: 1024, 640)
    #expect(MossGeometry.centered(box, in: PixelSize(width: 1024, height: 1024)) == [-464, -362, 16, 288])
  }

  @Test func fractionalEdgesFloorLeftTopAndCeilRightBottom() {
    let box = FracBox(x0: 0.3333, y0: 0, x1: 0.6667, y1: 1)
    #expect(MossGeometry.centered(box, in: PixelSize(width: 1536, height: 1024)) == [-512, -257, 512, 257])
  }

  @Test func aBoxOnePixelWideStaysInsideTheCanvas() {
    let box = FracBox(x0: 1 - 1.0 / 1024, y0: 0, x1: 1, y1: 1.0 / 640)
    let result = MossGeometry.centered(box, in: landscape)
    #expect(result == [-320, 511, -319, 512])
    #expect(result.allSatisfy { abs($0) <= 512 })
  }

  @Test func normalizedSortsClampsAndRejectsTinyBoxes() {
    let size = landscape
    let sorted = FracBox.normalized(x0: 0.8, y0: 0.9, x1: 0.2, y1: 0.1, size: size)
    #expect(sorted == FracBox(x0: 0.2, y0: 0.1, x1: 0.8, y1: 0.9))
    #expect(FracBox.normalized(x0: 0.5, y0: 0.5, x1: 1.4, y1: 0.9, size: size)?.x1 == 1)
    // lato minimo: il 2 % del lato corto (640 → 12,8 px = 0,0125 della larghezza, 0,02 dell'altezza)
    #expect(FracBox.normalized(x0: 0.1, y0: 0.1, x1: 0.11, y1: 0.5, size: size) == nil)
    #expect(FracBox.normalized(x0: 0.1, y0: 0.1, x1: 0.12, y1: 0.5, size: size) != nil)
    #expect(FracBox.normalized(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.11, size: size) == nil)
  }

  @Test func topLeftPixelsMatchTheDrawing() {
    let box = Self.frac(330, 150, 700, 640, in: 1024, 640)
    #expect(MossGeometry.topLeftPixels(box, in: landscape) == [330, 150, 700, 640])
  }

  @Test func centeredTextParsesBackToTheSameBox() {
    let box = Self.frac(330, 150, 700, 640, in: 1024, 640)
    let text = "[\(MossGeometry.centered(box, in: landscape).map(String.init).joined(separator: ", "))]"
    #expect(text == "[-170, -182, 320, 188]")
    let parsed = MossGeometry.parseCentered(text, current: box, size: landscape)
    #expect(parsed.map { MossGeometry.centered($0, in: landscape) } == [-170, -182, 320, 188])
  }

  @Test func centeredTextThatIsNotFourNumbersIsRejected() {
    let box = FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5)
    #expect(MossGeometry.parseCentered("abc", current: box, size: landscape) == nil)
    #expect(MossGeometry.parseCentered("[1, 2, 3]", current: box, size: landscape) == nil)
    #expect(MossGeometry.parseCentered("[100, 100, -100, -100]", current: box, size: landscape) != nil)
  }

  @Test func onlyMultiplesOfSixteenAreUsableSizes() {
    #expect(PixelSize(width: 1024, height: 640).isUsable)
    #expect(!PixelSize(width: 1000, height: 640).isUsable)
    #expect(!PixelSize(width: 0, height: 640).isUsable)
  }
}
