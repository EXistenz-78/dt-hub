import Foundation
import Testing

@testable import Panorama360

@Suite("Projection")
struct PSProjectionTests {
  static func sticker(yaw: Double = 0, pitch: Double = 0, rot: Double = 0, hfov: Double = 60, visible: Bool = true) -> Sticker {
    Sticker(name: "s", file: "s.png", yaw: yaw, pitch: pitch, rot: rot, hfov: hfov, visible: visible)
  }

  @Test func centerOfAStickerMapsToItsYawPitch() {
    let front = PSProjection.point(of: PSProjection.basis(for: Self.sticker(), aspect: 1.5).forward)
    #expect(abs(front.u - 0.5) < 1e-9 && abs(front.v - 0.5) < 1e-9)
    let right = PSProjection.point(of: PSProjection.basis(for: Self.sticker(yaw: 90), aspect: 1.5).forward)
    #expect(abs(right.u - 0.75) < 1e-9)
    let up = PSProjection.point(of: PSProjection.basis(for: Self.sticker(pitch: 45), aspect: 1.5).forward)
    #expect(abs(up.v - 0.25) < 1e-9)
  }

  @Test func erpRoundTrip() {
    for offset in [0.0, 0.5] {
      for (u, v) in [(0.1, 0.2), (0.5, 0.5), (0.93, 0.8)] {
        let back = PSProjection.point(of: PSProjection.direction(u: u, v: v, uOffset: offset), uOffset: offset)
        #expect(abs(back.u - u) < 1e-9 && abs(back.v - v) < 1e-9)
      }
    }
  }

  @Test func theOffsetShiftsTheColumns() {
    // With half a turn of offset the middle column looks at the back.
    let back = PSProjection.direction(u: 0.5, v: 0.5, uOffset: 0.5)
    #expect(abs(back.z + 1) < 1e-9)
  }

  @Test func yawWrapsAt180() {
    #expect(abs(PSProjection.wrapYaw(190) - (-170)) < 1e-9)
    #expect(abs(PSProjection.wrapYaw(-190) - 170) < 1e-9)
    #expect(abs(PSProjection.wrapYaw(360)) < 1e-9)
    #expect(abs(abs(PSProjection.wrapYaw(180)) - 180) < 1e-9)
  }

  @Test func verticalFOVFollowsTheAspect() {
    let expected = 2 * atan(tan(45 * Double.pi / 180) / 1.5) * 180 / Double.pi
    #expect(abs(PSProjection.verticalFOV(hfov: 90, aspect: 1.5) - expected) < 1e-9)
  }

  @Test func exifFocalGivesTheFieldOfView() {
    #expect(abs(PSProjection.horizontalFOV(focal35mm: 24, aspect: 1.5) - 73.74) < 0.05)
    #expect(abs(PSProjection.horizontalFOV(focal35mm: 28, aspect: 1.5) - 65.5) < 0.1)
    #expect(abs(PSProjection.horizontalFOV(focal35mm: 26, aspect: 4.0 / 3.0) - 67.3) < 0.3)
    // A portrait: the same focal sees less across its short side.
    #expect(abs(PSProjection.horizontalFOV(focal35mm: 28, aspect: 0.75) - 49.7) < 0.1)
    // Clamped to the sticker's range.
    #expect(PSProjection.horizontalFOV(focal35mm: 1, aspect: 1.5) == 170)
    #expect(PSProjection.horizontalFOV(focal35mm: 5000, aspect: 1.5) == 5)
  }

  @Test func planeCoordsInsideAndOutside() throws {
    let basis = PSProjection.basis(for: Self.sticker(hfov: 60), aspect: 1.5)
    let centre = try #require(PSProjection.planeCoords(basis.forward, in: basis))
    #expect(abs(centre.s - 0.5) < 1e-9 && abs(centre.t - 0.5) < 1e-9)
    #expect(PSProjection.planeCoords(PSProjection.direction(u: 0.5 + 80.0 / 360, v: 0.5), in: basis) == nil)
    #expect(PSProjection.planeCoords(PSProjection.direction(u: 0.0, v: 0.5), in: basis) == nil)
    // The right edge of a 60° sticker is 30° to the right: s = 1.
    let edge = PSProjection.planeCoords(PSProjection.direction(u: 0.5 + 29.9 / 360, v: 0.5), in: basis)
    #expect(edge != nil && edge!.s > 0.99)
  }

  @Test func hitTestPicksTheTopmostVisible() {
    let low = Self.sticker(), high = Self.sticker(), hidden = Self.sticker(visible: false)
    let list = [(sticker: low, aspect: 1.5), (sticker: high, aspect: 1.5), (sticker: hidden, aspect: 1.5)]
    #expect(PSProjection.hitTest(u: 0.5, v: 0.5, stickers: list) == high.id)
    #expect(PSProjection.hitTest(u: 0.05, v: 0.5, stickers: list) == nil)
  }

  @Test func aStraddlingStickerIsPickedOnBothSidesOfTheSeam() {
    let s = Self.sticker(yaw: 180)
    let list = [(sticker: s, aspect: 1.5)]
    #expect(PSProjection.hitTest(u: 0.01, v: 0.5, stickers: list) == s.id)
    #expect(PSProjection.hitTest(u: 0.99, v: 0.5, stickers: list) == s.id)
  }

  @Test func theOutlineIsSplitAtTheSeam() {
    let split = PSProjection.outline(of: Self.sticker(yaw: 180), aspect: 1.5)
    #expect(split.count >= 2)
    for line in split { for pair in zip(line, line.dropFirst()) { #expect(abs(pair.0.u - pair.1.u) < 0.5) } }
    #expect(PSProjection.outline(of: Self.sticker(), aspect: 1.5).count == 1)
  }

  @Test func theHandlesSitOnTheCornersAndAboveTheTopEdge() {
    let handles = PSProjection.handles(of: Self.sticker(), aspect: 1.5)
    #expect(handles.corners.count == 4)
    #expect(abs(handles.center.u - 0.5) < 1e-9 && abs(handles.center.v - 0.5) < 1e-9)
    #expect(handles.rotate.v < handles.corners[0].v)
  }
}
