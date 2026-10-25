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

  // MARK: The view from the camera, a panorama as background, the feather

  /// A panorama whose columns are told apart by colour: red in a band around u = 0.5, blue around u = 0.75, white at the top.
  func panorama() -> CGImage {
    TestImages.make(256, 128) { x, y in
      if y < 12 { return (255, 255, 255, 255) }
      if (112..<144).contains(x) { return (255, 0, 0, 255) }
      if (176..<208).contains(x) { return (0, 0, 255, 255) }
      return (40, 40, 40, 255)
    }
  }

  @Test func aViewOfNothingIsPureGreen() throws {
    for (name, renderer) in Self.renderers() {
      let image = try renderer.renderView(.layers([]), camera: PSCamera(), width: 64, height: 48)
      #expect(image.width == 64 && image.height == 48, "\(name)")
      for (x, y) in [(0, 0), (32, 24), (63, 47)] {
        let p = TestImages.pixel(image, x, y)
        #expect(p.r == 0 && p.g == 255 && p.b == 0 && p.a == 255, "\(name) \(p)")
      }
    }
  }

  @Test func theViewLooksWhereTheCameraLooks() throws {
    let red = TestImages.layer(TestImages.solid(30, 20, 255, 0, 0), yaw: 0, hfov: 50)
    let blue = TestImages.layer(TestImages.solid(30, 20, 0, 0, 255), yaw: 90, hfov: 50)
    for (name, renderer) in Self.renderers() {
      func centre(_ yaw: Double) throws -> (r: Int, g: Int, b: Int, a: Int) {
        let image = try renderer.renderView(.layers([red, blue]), camera: PSCamera(yaw: yaw, pitch: 0, fov: 60), width: 128, height: 96)
        return TestImages.pixel(image, 64, 48)
      }
      let ahead = try centre(0), right = try centre(90), back = try centre(180)
      #expect(ahead.r == 255 && ahead.b == 0, "\(name) ahead \(ahead)")
      #expect(right.b == 255 && right.r == 0, "\(name) right \(right)")
      #expect(back.g == 255 && back.r == 0, "\(name) back \(back)")
    }
  }

  @Test func aStickerOnTheSeamIsWholeInTheView() throws {
    let blue = TestImages.layer(TestImages.solid(30, 20, 0, 0, 255), yaw: 180, hfov: 80)
    for (name, renderer) in Self.renderers() {
      let image = try renderer.renderView(.layers([blue]), camera: PSCamera(yaw: 180, pitch: 0, fov: 60), width: 128, height: 96)
      for x in stride(from: 8, to: 120, by: 16) { #expect(TestImages.pixel(image, x, 48).b == 255, "\(name) x \(x)") }
    }
  }

  @Test func aPanoramaIsSampledByDirection() throws {
    let pano = panorama()
    for (name, renderer) in Self.renderers() {
      func centre(yaw: Double, pitch: Double = 0) throws -> (r: Int, g: Int, b: Int, a: Int) {
        TestImages.pixel(try renderer.renderView(.panorama(pano), camera: PSCamera(yaw: yaw, pitch: pitch, fov: 40), width: 64, height: 48), 32, 24)
      }
      let front = try centre(yaw: 0), right = try centre(yaw: 90), left = try centre(yaw: -90), up = try centre(yaw: 0, pitch: 88)
      #expect(front.r == 255 && front.b == 0, "\(name) front \(front)")
      #expect(right.b == 255 && right.r == 0, "\(name) right \(right)")
      #expect(left.r == 40 && left.b == 40, "\(name) left \(left)")
      #expect(up.r > 200 && up.g > 200 && up.b > 200, "\(name) looking up \(up)")
      // The longitude wraps: a view across the seam (yaw 180) is continuous, never green.
      let seam = try renderer.renderView(.panorama(pano), camera: PSCamera(yaw: 180, pitch: 0, fov: 60), width: 64, height: 48)
      for x in [0, 31, 63] { #expect(TestImages.pixel(seam, x, 24).g != 255 || TestImages.pixel(seam, x, 24).r != 0, "\(name) seam \(x)") }
    }
  }

  @Test func aBackgroundReplacesTheGreen() throws {
    let solid = TestImages.solid(64, 32, 10, 20, 200)
    let red = TestImages.layer(TestImages.solid(30, 20, 255, 0, 0))
    for (name, renderer) in Self.renderers() {
      let plain = try renderer.render([], width: 128, height: 64, uOffset: 0, background: solid)
      for (x, y) in [(0, 0), (64, 32), (127, 63)] {
        let p = TestImages.pixel(plain, x, y)
        #expect(abs(p.r - 10) <= 1 && abs(p.g - 20) <= 1 && abs(p.b - 200) <= 1, "\(name) \(p)")
      }
      let over = try renderer.render([red], width: 128, height: 64, uOffset: 0, background: solid)
      #expect(TestImages.pixel(over, 64, 32).r == 255 && abs(TestImages.pixel(over, 4, 4).b - 200) <= 1, "\(name)")
    }
  }

  @Test func theBackgroundIsPlacedLikeThePanoramaViewSeesIt() throws {
    let pano = panorama()
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([], width: 256, height: 128, uOffset: 0, background: pano)
      let a = PSPixels.rgba(of: pano).bytes, b = PSPixels.rgba(of: image).bytes
      var worst = 0
      for i in 0..<a.count where i % 4 != 3 { worst = max(worst, abs(Int(a[i]) - Int(b[i]))) }
      #expect(worst <= 3, "\(name) worst \(worst)")
    }
  }

  @Test func featherSoftensTheEdgeOfALayer() throws {
    var layer = TestImages.layer(TestImages.solid(40, 40, 255, 0, 0), hfov: 90)
    layer.feather = 0.2
    for (name, renderer) in Self.renderers() {
      let image = try renderer.render([layer], width: 512, height: 256, uOffset: 0)
      // Walk from the centre of the layer to its edge along the equator: red falls off monotonically towards green.
      var last = 256
      var seenSoft = false
      for x in stride(from: 256, to: 320, by: 2) {
        let p = TestImages.pixel(image, x, 128)
        if p.r < 250 && p.r > 5 { seenSoft = true }
        #expect(p.r <= last + 1, "\(name) x \(x) \(p)")
        last = p.r
      }
      #expect(seenSoft && TestImages.pixel(image, 256, 128).r == 255, "\(name)")
    }
  }

  @Test func metalMatchesTheCPUOnViewsAndBackgrounds() throws {
    guard let metal = try? PSMetalRenderer() else { return }
    var feathered = TestImages.layer(TestImages.gradient(50, 50, seed: 3), yaw: 10, pitch: 5, rot: 15, hfov: 60, opacity: 0.9)
    feathered.feather = 0.1
    let layers = [TestImages.layer(TestImages.gradient(60, 40, seed: 1), yaw: -40, pitch: 10, hfov: 80), feathered]
    let pano = TestImages.gradient(128, 64, seed: 2)
    let camera = PSCamera(yaw: -20, pitch: 12, fov: 75)
    func compare(_ a: CGImage, _ b: CGImage, _ what: String) {
      let pa = PSPixels.rgba(of: a).bytes, pb = PSPixels.rgba(of: b).bytes
      var total = 0, worst = 0
      for i in 0..<pa.count { let d = abs(Int(pa[i]) - Int(pb[i])); total += d; worst = max(worst, d) }
      #expect(Double(total) / Double(pa.count) < 2 && worst <= 14, "\(what): mean \(Double(total) / Double(pa.count)) worst \(worst)")
    }
    let cpu = PSCPURenderer()
    compare(try cpu.renderView(.layers(layers), camera: camera, width: 256, height: 192), try metal.renderView(.layers(layers), camera: camera, width: 256, height: 192), "view layers")
    compare(try cpu.renderView(.panorama(pano), camera: camera, width: 256, height: 192), try metal.renderView(.panorama(pano), camera: camera, width: 256, height: 192), "view panorama")
    compare(try cpu.render(layers, width: 256, height: 128, uOffset: 0, background: pano), try metal.render(layers, width: 256, height: 128, uOffset: 0, background: pano), "background")
  }

  @Test func aViewKeepsTheDetailOfASticker() throws {
    // A 1-pixel black line on white, magnified: the view samples the picture itself, so the line stays black at its centre.
    let line = TestImages.make(65, 65) { x, _ in x == 32 ? (0, 0, 0, 255) : (255, 255, 255, 255) }
    for (name, renderer) in Self.renderers() {
      let image = try renderer.renderView(.layers([TestImages.layer(line, hfov: 60)]), camera: PSCamera(yaw: 0, pitch: 0, fov: 30), width: 256, height: 192)
      var darkest = 255
      for x in 0..<256 { darkest = min(darkest, TestImages.pixel(image, x, 96).r) }
      #expect(darkest <= 30, "\(name) darkest \(darkest)")
    }
  }
}
