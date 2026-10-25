import CoreGraphics
import Foundation
import Testing

@testable import Panorama360

@Suite("Camera")
struct PSCameraTests {
  func close(_ a: Vec3, _ b: Vec3, _ tolerance: Double = 1e-9) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
  }

  @Test func theCentreRayLooksAlongTheCamera() {
    for camera in [PSCamera(), PSCamera(yaw: 40, pitch: -20, fov: 60), PSCamera(yaw: -170, pitch: 60, fov: 120)] {
      #expect(close(camera.ray(x: 512, y: 384, width: 1024, height: 768), camera.basis.forward))
    }
  }

  @Test func rayAndScreenPointAreInverse() throws {
    for camera in [PSCamera(yaw: 40, pitch: -20, fov: 60), PSCamera(yaw: 0, pitch: 0, fov: 120)] {
      for (x, y) in [(10.0, 10.0), (512.0, 100.0), (1000.0, 700.0), (300.5, 400.25)] {
        let d = camera.ray(x: x, y: y, width: 1024, height: 768)
        let p = try #require(camera.screenPoint(of: d, width: 1024, height: 768))
        #expect(abs(p.x - x) < 1e-6 && abs(p.y - y) < 1e-6, "\(camera) \(x),\(y) → \(p)")
      }
    }
  }

  @Test func theRightEdgeOfTheViewIsHalfTheFOVToTheRight() {
    let camera = PSCamera(yaw: 0, pitch: 0, fov: 90)
    let d = camera.ray(x: 1024, y: 384, width: 1024, height: 768)
    #expect(abs(atan2(d.x, d.z) * 180 / .pi - 45) < 1e-9)
  }

  @Test func aDirectionBehindTheCameraHasNoScreenPoint() {
    let camera = PSCamera(yaw: 0, pitch: 0, fov: 60)
    #expect(camera.screenPoint(of: Vec3(x: 0, y: 0, z: -1), width: 1024, height: 768) == nil)
    #expect(camera.screenPoint(of: Vec3(x: 1, y: 0, z: 0), width: 1024, height: 768) == nil)
    let wide = PSProjection.direction(u: 0.5 + 80.0 / 360, v: 0.5)
    let p = camera.screenPoint(of: wide, width: 1024, height: 768)
    #expect(p != nil && p!.x > 1024)
  }

  @Test func lookingDragsTheSceneTheOtherWay() {
    var camera = PSCamera(yaw: 0, pitch: 0, fov: 90)
    camera.look(dx: 10, dy: 10, width: 1024)
    #expect(abs(camera.yaw - (-10 * 90 / 1024)) < 1e-9)
    #expect(abs(camera.pitch - (10 * 90 / 1024)) < 1e-9)
    camera.look(dx: 0, dy: 100_000, width: 1024)
    #expect(camera.pitch == 89)
    camera = PSCamera(yaw: 179, pitch: 0, fov: 90)
    camera.look(dx: -100, dy: 0, width: 1024)
    #expect(camera.yaw < -170 && camera.yaw > -180)
  }

  @Test func zoomClampsTheFieldOfView() {
    var camera = PSCamera()
    camera.zoom(by: 1000)
    #expect(camera.fov == 120)
    camera.zoom(by: -0.99)
    #expect(camera.fov == 20)
    camera.zoom(by: 0.5)
    #expect(abs(camera.fov - 30) < 1e-9)
  }

  @Test func clampBringsEverythingIntoRange() {
    var camera = PSCamera(yaw: 190, pitch: 95, fov: 500)
    camera.clamp()
    #expect(abs(camera.yaw - (-170)) < 1e-9 && camera.pitch == 89 && camera.fov == 120)
  }

  @Test func theCameraRoundTripsThroughJSON() throws {
    let camera = PSCamera(yaw: 12, pitch: -7, fov: 75)
    #expect(try JSONDecoder().decode(PSCamera.self, from: JSONEncoder().encode(camera)) == camera)
  }

  @Test func aCameraOutOfRangeInTheFileIsClampedOnLoad() throws {
    let folder = PSModelsTests.folder()
    try Data(#"{"version":1,"stickers":[],"description":"","mode":"normal","guides":true,"camera":{"yaw":400,"pitch":120,"fov":0}}"#.utf8)
      .write(to: folder.appendingPathComponent("state.json"))
    let camera = PanoState.load(from: folder).camera
    #expect(camera.fov == 20 && camera.pitch == 89 && abs(camera.yaw - 40) < 1e-9)
  }
}
