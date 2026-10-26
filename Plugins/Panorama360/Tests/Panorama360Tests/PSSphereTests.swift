import CoreGraphics
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Sphere")
struct PSSphereTests {
  let size = CGSize(width: 1024, height: 768)
  var centre: CGPoint { CGPoint(x: 512, y: 384) }

  func sticker(yaw: Double = 0, pitch: Double = 0, hfov: Double = 40) -> Sticker {
    Sticker(name: "s", file: "s.png", yaw: yaw, pitch: pitch, hfov: hfov)
  }

  /// A state with these stickers (3:2 pictures), the last selected, and the camera where it is by default.
  func state(_ list: [Sticker], source: PSSource = .canvas) -> PSState {
    let state = PSState(italian: false)
    state.mutate {
      $0.stickers = list
      $0.selectedID = list.last?.id
      $0.viewMode = .sphere
      $0.source = source
    }
    for s in list { state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: s.id) }
    return state
  }

  func lon(_ camera: PSCamera, _ p: CGPoint) -> Double {
    let d = camera.ray(x: p.x, y: p.y, width: size.width, height: size.height)
    return atan2(d.x, d.z) * 180 / .pi
  }

  // MARK: Pure projection

  @Test func theOutlineOfAStickerInFrontIsOneClosedLineInsideTheView() throws {
    let lines = PSSphere.outline(of: sticker(), aspect: 1.5, camera: PSCamera(), size: size)
    #expect(lines.count == 1)
    let line = try #require(lines.first)
    #expect(line.first == line.last)
    for p in line { #expect(p.x > 0 && p.x < size.width && p.y > 0 && p.y < size.height) }
  }

  @Test func aStickerHalfBehindTheCameraIsCutToItsFrontPart() {
    let lines = PSSphere.outline(of: sticker(yaw: 90, hfov: 120), aspect: 1.5, camera: PSCamera(), size: size)
    let points = lines.reduce(0) { $0 + $1.count }
    #expect(!lines.isEmpty && points > 0 && points < 4 * 28 + 1)
    for line in lines { for p in line { #expect(p.x.isFinite && p.y.isFinite) } }
  }

  @Test func aStickerEntirelyBehindHasNoOutlineNoHandlesAndIsNotHit() {
    let behind = sticker(yaw: 180)
    #expect(PSSphere.outline(of: behind, aspect: 1.5, camera: PSCamera(), size: size).allSatisfy { $0.isEmpty })
    #expect(PSSphere.handles(of: behind, aspect: 1.5, camera: PSCamera(), size: size).center == nil)
    #expect(PSSphere.hit(at: centre, stickers: [(behind, 1.5)], camera: PSCamera(), size: size) == nil)
    #expect(PSSphere.hit(at: centre, stickers: [(behind, 1.5)], camera: PSCamera(yaw: 180), size: size) == behind.id)
  }

  @Test func theHandlesAreWhereTheCornersProject() throws {
    let h = PSSphere.handles(of: sticker(), aspect: 1.5, camera: PSCamera(), size: size)
    let c = try #require(h.center), tl = try #require(h.corners[0]), tr = try #require(h.corners[1]), rot = try #require(h.rotate)
    #expect(abs(c.x - 512) < 1e-6 && abs(c.y - 384) < 1e-6)
    #expect(abs((tl.x + tr.x) - 1024) < 1e-6 && abs(tl.y - tr.y) < 1e-6 && tl.y < c.y)
    #expect(rot.y < tl.y)
  }

  // MARK: Pointer

  @Test func aClickOnAStickerSelectsTheTopmostOne() {
    let low = sticker(yaw: 0), high = sticker(yaw: 5)
    let state = state([low, high])
    state.select(low.id)
    state.spherePointerDown(at: centre, size: size)
    state.spherePointerUp()
    #expect(state.doc.selectedID == high.id)
  }

  @Test func dragMovesTheStickerWithTheGrabOffset() {
    let s = sticker(hfov: 60)
    let state = state([s])
    let from = CGPoint(x: 562, y: 384), to = CGPoint(x: 662, y: 384)
    state.spherePointerDown(at: from, size: size)
    state.spherePointerDragged(to: to, size: size, shift: false)
    state.spherePointerUp()
    let camera = PSCamera()
    #expect(abs(state.doc.stickers[0].yaw - (lon(camera, to) - lon(camera, from))) < 1e-6)
    #expect(abs(state.doc.stickers[0].pitch) < 1e-6)
  }

  @Test func dragFromACornerScalesByTheRatioOfScreenDistances() throws {
    let s = sticker(hfov: 40)
    let state = state([s])
    let h = PSSphere.handles(of: s, aspect: 1.5, camera: PSCamera(), size: size)
    let c = try #require(h.center), corner = try #require(h.corners[1])
    state.spherePointerDown(at: corner, size: size)
    state.spherePointerDragged(to: CGPoint(x: c.x + (corner.x - c.x) * 2, y: c.y + (corner.y - c.y) * 2), size: size, shift: false)
    state.spherePointerUp()
    #expect(abs(state.doc.stickers[0].hfov - 80) < 1e-6)
  }

  @Test func dragFromTheRotateHandleRotatesAndShiftSnaps() throws {
    let s = sticker(hfov: 40)
    let state = state([s])
    let h = PSSphere.handles(of: s, aspect: 1.5, camera: PSCamera(), size: size)
    let c = try #require(h.center), handle = try #require(h.rotate)
    func at(_ degrees: Double) -> CGPoint {
      let a = (-90 + degrees) * .pi / 180
      return CGPoint(x: c.x + 100 * cos(a), y: c.y + 100 * sin(a))
    }
    state.spherePointerDown(at: handle, size: size)
    state.spherePointerDragged(to: at(20), size: size, shift: false)
    #expect(abs(state.doc.stickers[0].rot - 20) < 0.01)
    state.spherePointerDragged(to: at(30), size: size, shift: true)
    #expect(state.doc.stickers[0].rot == 45)
    state.spherePointerUp()
  }

  @Test func draggingTheEmptyViewLooksAround() {
    let s = sticker(hfov: 20)
    let state = state([s])
    let before = state.doc.stickers
    state.spherePointerDown(at: CGPoint(x: 50, y: 50), size: size)
    state.spherePointerDragged(to: CGPoint(x: 150, y: 50), size: size, shift: false)
    state.spherePointerUp()
    #expect(abs(state.doc.camera.yaw - (-100 * 90 / 1024)) < 1e-9)
    #expect(state.doc.stickers == before && state.doc.selectedID == s.id)
  }

  @Test func inTheResultNothingIsEditableButTheViewStillLooksAround() {
    let s = sticker()
    let state = state([s], source: .result)
    let result = TestImages.file(TestImages.solid(256, 128, 1, 2, 3), in: TestImages.tempFolder(), name: "r.png", type: "public.png")
    state.apply(context: Data(#"{"type":"context","tempFolder":"/t","lastResult":{"path":"\#(result.path)","name":"r.png"}}"#.utf8))
    let before = state.doc.stickers
    state.spherePointerDown(at: centre, size: size)
    state.spherePointerDragged(to: CGPoint(x: 612, y: 384), size: size, shift: false)
    state.spherePointerUp()
    #expect(state.doc.stickers == before)
    #expect(state.doc.camera.yaw != 0)
  }

  @Test func zoomAndResetWork() {
    let state = state([sticker()])
    state.sphereZoom(by: 1)
    #expect(state.camera.fov == 160)
    state.spherePointerDown(at: CGPoint(x: 50, y: 50), size: size)
    state.spherePointerDragged(to: CGPoint(x: 150, y: 90), size: size, shift: false)
    state.spherePointerUp()
    state.resetCamera()
    #expect(state.camera == PSCamera())
  }

  @Test func aCameraAtThePoleStillSeesAStickerThereAndItsOutlineIsFinite() throws {
    for pitch in [85.0, -85.0] {
      let camera = PSCamera(yaw: 0, pitch: pitch >= 0 ? 89 : -89, fov: 90)
      let s = sticker(yaw: 0, pitch: pitch, hfov: 40)
      let lines = PSSphere.outline(of: s, aspect: 1.5, camera: camera, size: size)
      #expect(!lines.isEmpty && lines.allSatisfy { $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
      #expect(PSSphere.hit(at: centre, stickers: [(s, 1.5)], camera: camera, size: size) == s.id)
    }
  }
}
