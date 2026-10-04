import AppKit
import SwiftUI
import Testing

@testable import SphereLight

@Suite("SphereRenderer")
struct SphereRendererTests {
  private let size = 96

  private func light(rotation: Double, elevation: Double = 20) -> LightParams {
    LightParams(
      rotationDeg: rotation, elevationDeg: elevation, intensity: 1.5, hardness: 0.65, color: .white)
  }

  /// The mean grey of a rectangle of the picture (fractions of its width and height).
  private func brightness(_ pixels: [UInt8], x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
    var sum = 0.0
    var count = 0.0
    for py in Int(y.lowerBound * Double(size))..<Int(y.upperBound * Double(size)) {
      for px in Int(x.lowerBound * Double(size))..<Int(x.upperBound * Double(size)) {
        let i = (py * size + px) * 3
        sum += Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])
        count += 3
      }
    }
    return sum / count
  }

  @Test func theBufferHasThreeBytesPerPixel() {
    let pixels = SphereRenderer.render(width: size, height: size, lights: [light(rotation: 90)], shadowSampleCount: 4)
    #expect(pixels.count == size * size * 3)
  }

  @Test func noLightsGivesABlackPicture() {
    let pixels = SphereRenderer.render(width: 8, height: 8, lights: [], shadowSampleCount: 4)
    #expect(pixels == [UInt8](repeating: 0, count: 8 * 8 * 3))
  }

  @Test func theSideTheLightComesFromIsBrighter() {
    let left = 0.36...0.48
    let right = 0.52...0.64
    let rows = 0.36...0.45
    let fromRight = SphereRenderer.render(width: size, height: size, lights: [light(rotation: 90)], shadowSampleCount: 4)
    let fromLeft = SphereRenderer.render(width: size, height: size, lights: [light(rotation: -90)], shadowSampleCount: 4)
    #expect(brightness(fromRight, x: right, y: rows) > brightness(fromRight, x: left, y: rows) + 20)
    #expect(brightness(fromLeft, x: left, y: rows) > brightness(fromLeft, x: right, y: rows) + 20)
  }

  @Test func differentLightsGiveDifferentPictures() {
    let a = SphereRenderer.render(width: 48, height: 48, lights: [light(rotation: 90)], shadowSampleCount: 4)
    let b = SphereRenderer.render(width: 48, height: 48, lights: [light(rotation: -90)], shadowSampleCount: 4)
    #expect(a != b)
  }

  @Test func thePNGDecodesToTheSameSize() throws {
    let pixels = SphereRenderer.render(width: 64, height: 64, lights: [light(rotation: 45)], shadowSampleCount: 4)
    let png = try #require(SphereRenderer.pngData(fromRGB8: pixels, width: 64, height: 64))
    let rep = try #require(NSBitmapImageRep(data: png))
    #expect(rep.pixelsWide == 64 && rep.pixelsHigh == 64)
  }

  @Test func theDefaultLightsAreTheOnesOfTheApp() {
    #expect(LightParams.makeDefault(index: 0).rotationDeg == -135)
    #expect(LightParams.makeDefault(index: 1).elevationDeg == 55)
    #expect(LightParams.makeDefault(index: 2).hardness == 0.3)
  }
}
