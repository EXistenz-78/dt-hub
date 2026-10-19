import CoreGraphics
import Testing

@testable import TiledUpscaleLab

struct TUToneTests {
  private func gray(_ width: Int, _ height: Int, _ value: UInt8) -> CGImage { TestImages.solid(width, height, (value, value, value)) }
  private func level(_ image: CGImage, _ x: Int, _ y: Int) -> Int { Int(TestImages.pixel(image, x, y)[0]) }

  @Test func aUniformShiftIsBroughtBackToTheSource() throws {
    let out = try #require(TUTone.correct(result: gray(128, 128, 130), base: gray(128, 128, 100), maskRect: nil, radius: 16, strength: 1))
    #expect(abs(level(out, 64, 64) - 100) <= 1)
    #expect(abs(level(out, 3, 3) - 100) <= 1, "also at the edge of the tile")
  }

  @Test func theStrengthIsTheShareOfTheCorrection() throws {
    let half = try #require(TUTone.correct(result: gray(64, 64, 130), base: gray(64, 64, 100), maskRect: nil, radius: 16, strength: 0.5))
    #expect(abs(level(half, 32, 32) - 115) <= 1)
    let none = try #require(TUTone.correct(result: gray(64, 64, 130), base: gray(64, 64, 100), maskRect: nil, radius: 16, strength: 0))
    #expect(level(none, 32, 32) == 130)
  }

  @Test func aDarkerResultIsLightenedAndTheHueIsKept() throws {
    let result = TestImages.solid(64, 64, (80, 40, 20))   // twice darker than the source
    let base = TestImages.solid(64, 64, (160, 80, 40))
    let out = try #require(TUTone.correct(result: result, base: base, maskRect: nil, radius: 16, strength: 1))
    let p = TestImages.pixel(out, 32, 32)
    #expect(abs(Int(p[0]) - 160) <= 3 && abs(Int(p[1]) - 80) <= 3 && abs(Int(p[2]) - 40) <= 3)
  }

  @Test func theDetailOfTheResultStays() throws {
    // A fine pattern around 130 against a flat 100: the pattern is still there (scaled by the gain), not flattened.
    var bytes = [UInt8](repeating: 255, count: 64 * 64 * 4)
    for y in 0..<64 { for x in 0..<64 { let v: UInt8 = (x + y) % 2 == 0 ? 150 : 110; for c in 0..<3 { bytes[(y * 64 + x) * 4 + c] = v } } }
    let result = try #require(TUImage.image(rgba: bytes, width: 64, height: 64))
    let out = try #require(TUTone.correct(result: result, base: gray(64, 64, 100), maskRect: nil, radius: 8, strength: 1))
    let contrast = abs(level(out, 20, 20) - level(out, 21, 20))
    #expect(contrast >= 25, "the pattern had a swing of 40; it is about 31 after the gain")
    #expect(abs((level(out, 20, 20) + level(out, 21, 20)) / 2 - 100) <= 3, "and its mean is the source's")
  }

  @Test func theFreePartIsLeftAloneAndTheCorrectionGrowsInside() throws {
    let masked = TileRect(x: 64, y: 0, width: 192, height: 128)
    let out = try #require(TUTone.correct(result: gray(256, 128, 130), base: gray(256, 128, 100), maskRect: masked, radius: 16, strength: 1))
    #expect(level(out, 10, 64) == 130, "the free part is not touched")
    #expect(level(out, 64, 64) > 125, "at the edge of the mask the correction is only starting")
    #expect(abs(level(out, 200, 64) - 100) <= 1, "well inside it is complete")
  }

  @Test func aShiftOfThreeTimesIsBroughtBack() throws {
    // A night sky: the source is at 30, the model made it 90. A correction limited to half would leave it at 45.
    let out = try #require(TUTone.correct(result: gray(128, 128, 90), base: gray(128, 128, 30), maskRect: nil, radius: 24, strength: 1))
    #expect(abs(level(out, 64, 64) - 30) <= 2)
    let brighter = try #require(TUTone.correct(result: gray(128, 128, 30), base: gray(128, 128, 90), maskRect: nil, radius: 24, strength: 1))
    #expect(abs(level(brighter, 64, 64) - 90) <= 5, "and the other way (the +2 that keeps a black from dividing by zero costs a few levels)")
  }

  @Test func theGainIsStillLimited() throws {
    let out = try #require(TUTone.correct(result: gray(64, 64, 200), base: gray(64, 64, 4), maskRect: nil, radius: 16, strength: 1))
    #expect(level(out, 32, 32) >= 39 && level(out, 32, 32) <= 41, "it never scales by less than a fifth: 200 → 40")
  }
}
