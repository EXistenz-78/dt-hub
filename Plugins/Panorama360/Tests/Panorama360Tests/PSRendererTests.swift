import CoreGraphics
import Metal
import Testing

@testable import Panorama360

@Suite("Renderers")
struct PSRendererTests {
  /// Every renderer there is on this machine: the CPU one, and the Metal one when there is a device.
  static func renderers() -> [(name: String, renderer: any PSRendering)] {
    var list: [(String, any PSRendering)] = [("cpu", PSCPURenderer())]
    if let metal = try? PSMetalRenderer() { list.append(("metal", metal)) }
    return list
  }

  @Test func theMetalRendererIsThereWhenTheMachineHasAGPU() {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    #expect(Self.renderers().map(\.name) == ["cpu", "metal"])
    #expect(PSRendererFactory.make() is PSMetalRenderer)
  }

  @Test func emptySceneIsPureGreen() throws {
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([], width: 64, height: 32, uOffset: 0)
      #expect(image.width == 64 && image.height == 32, "\(name)")
      for (x, y) in [(0, 0), (31, 15), (63, 31)] {
        let p = TestImages.pixel(image, x, y)
        #expect(p.r == 0 && p.g == 255 && p.b == 0 && p.a == 255, "\(name) \(x),\(y) \(p)")
      }
    }
  }

  @Test func aCentredStickerFillsItsPlaceAndNothingElse() throws {
    let red = TestImages.solid(30, 20, 255, 0, 0)
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([TestImages.layer(red)], width: 512, height: 256, uOffset: 0)
      let centre = TestImages.pixel(image, 256, 128)
      #expect(centre.r == 255 && centre.g == 0, "\(name) centre \(centre)")
      let corner = TestImages.pixel(image, 10, 10)
      #expect(corner.r == 0 && corner.g == 255, "\(name) corner \(corner)")
    }
  }

  @Test func opacityBlends() throws {
    let red = TestImages.solid(30, 20, 255, 0, 0)
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([TestImages.layer(red, opacity: 0.5)], width: 512, height: 256, uOffset: 0)
      let p = TestImages.pixel(image, 256, 128)
      #expect(abs(p.r - 128) <= 2 && abs(p.g - 128) <= 2 && p.b == 0, "\(name) \(p)")
    }
  }

  @Test func alphaIsComposited() throws {
    let half = TestImages.make(40, 20) { x, _ in x < 20 ? (255, 0, 0, 255) : (255, 0, 0, 0) }
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([TestImages.layer(half)], width: 512, height: 256, uOffset: 0)
      let left = TestImages.pixel(image, 220, 128)
      let right = TestImages.pixel(image, 300, 128)
      #expect(left.r == 255 && left.g == 0, "\(name) left \(left)")
      #expect(right.r == 0 && right.g == 255, "\(name) right \(right)")
    }
  }

  @Test func zOrderLastOnTop() throws {
    let red = TestImages.solid(30, 20, 255, 0, 0)
    let blue = TestImages.solid(30, 20, 0, 0, 255)
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([TestImages.layer(red), TestImages.layer(blue)], width: 256, height: 128, uOffset: 0)
      let p = TestImages.pixel(image, 128, 64)
      #expect(p.b == 255 && p.r == 0, "\(name) \(p)")
    }
  }

  @Test func seamStickerIsContinuous() throws {
    let blue = TestImages.solid(30, 20, 0, 0, 255)
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([TestImages.layer(blue, yaw: 180)], width: 512, height: 256, uOffset: 0)
      let left = TestImages.pixel(image, 0, 128)
      let right = TestImages.pixel(image, 511, 128)
      #expect(left.b == 255 && right.b == 255, "\(name) \(left) \(right)")
    }
  }

  @Test func uOffsetShiftsThePicture() throws {
    let red = TestImages.solid(30, 20, 255, 0, 0)
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([TestImages.layer(red)], width: 512, height: 256, uOffset: 0.5)
      let p0 = TestImages.pixel(image, 0, 128)
      let p1 = TestImages.pixel(image, 511, 128)
      let middle = TestImages.pixel(image, 256, 128)
      #expect(p0.r == 255 && p1.r == 255 && middle.g == 255, "\(name) \(p0) \(p1) \(middle)")
    }
  }

  @Test func metalMatchesTheCPU() throws {
    guard let metal = try? PSMetalRenderer() else { return }
    let layers = [
      TestImages.layer(TestImages.gradient(60, 40, seed: 1), yaw: -40, pitch: 10, hfov: 80),
      TestImages.layer(TestImages.make(50, 50) { x, y in ((x / 5 + y / 5) % 2 == 0 ? (250, 250, 0, 200) : (0, 30, 200, 255)) }, yaw: 20, pitch: -5, rot: 25, hfov: 60, opacity: 0.8),
      TestImages.layer(TestImages.gradient(40, 60, seed: 2), yaw: 175, pitch: 0, hfov: 50),
    ]
    let a = try PSCPURenderer().render(layers, width: 512, height: 256, uOffset: 0)
    let b = try metal.render(layers, width: 512, height: 256, uOffset: 0)
    let pa = PSPixels.rgba(of: a).bytes, pb = PSPixels.rgba(of: b).bytes
    var total = 0, worst = 0
    for i in 0..<pa.count { let d = abs(Int(pa[i]) - Int(pb[i])); total += d; worst = max(worst, d) }
    let mean = Double(total) / Double(pa.count)
    #expect(mean < 2, "mean difference \(mean)")
    #expect(worst <= 12, "worst difference \(worst)")
  }

  @Test func theMetalTextureCacheKeepsOnlyWhatWasDrawnLast() throws {
    guard let metal = try? PSMetalRenderer() else { return }
    let a = TestImages.layer(TestImages.solid(20, 20, 255, 0, 0)), b = TestImages.layer(TestImages.solid(20, 20, 0, 0, 255))
    _ = try metal.render([a, b], width: 64, height: 32, uOffset: 0)
    #expect(metal.cachedTextureCount == 2)
    _ = try metal.render([b], width: 64, height: 32, uOffset: 0)
    #expect(metal.cachedTextureCount == 1)
    _ = try metal.render([], width: 64, height: 32, uOffset: 0)
    #expect(metal.cachedTextureCount == 0)
  }
}
