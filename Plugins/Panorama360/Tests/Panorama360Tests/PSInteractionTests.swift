import Foundation
import Testing

@testable import Panorama360

@Suite("Interaction")
struct PSInteractionTests {
  private func u(forLon lon: Double) -> Double { lon / 360 + 0.5 }

  @Test func moveKeepsTheGrabOffset() {
    let s = PSProjectionTests.sticker(yaw: 20)
    let grab = PSInteraction.grab(s, at: (u: u(forLon: 30), v: 0.5))
    let moved = PSInteraction.moved(s, to: (u: u(forLon: 40), v: 0.5), grab: grab)
    #expect(abs(moved.yaw - 30) < 1e-9)
    #expect(abs(moved.pitch) < 1e-9)
  }

  @Test func moveCrossingTheSeamWraps() {
    let s = PSProjectionTests.sticker(yaw: 175)
    let grab = PSInteraction.grab(s, at: (u: u(forLon: 175), v: 0.5))
    let moved = PSInteraction.moved(s, to: (u: u(forLon: -175), v: 0.5), grab: grab)
    #expect(abs(moved.yaw - (-175)) < 1e-9)
  }

  @Test func pitchIsClampedTo89() {
    let s = PSProjectionTests.sticker()
    let moved = PSInteraction.moved(s, to: (u: 0.5, v: 0.0), grab: PSInteraction.Grab(yaw: 0, pitch: 0))
    #expect(moved.pitch == 89)
  }

  @Test func scaleIsTheRatioOfDistancesAndClamped() {
    let s = PSProjectionTests.sticker(hfov: 60)
    #expect(abs(PSInteraction.scaled(s, startFOV: 60, startDistance: 50, distance: 100).hfov - 120) < 1e-9)
    #expect(PSInteraction.scaled(s, startFOV: 60, startDistance: 50, distance: 500).hfov == 170)
    #expect(PSInteraction.scaled(s, startFOV: 60, startDistance: 50, distance: 1).hfov == 5)
  }

  @Test func rotateFollowsThePointerAndShiftSnapsTo45() {
    let s = PSProjectionTests.sticker(rot: 10)
    let free = PSInteraction.rotated(s, startRot: 10, startAngle: 0, angle: 20 * .pi / 180, snap: false)
    #expect(abs(free.rot - 30) < 1e-9)
    let snapped = PSInteraction.rotated(s, startRot: 10, startAngle: 0, angle: 20 * .pi / 180, snap: true)
    #expect(snapped.rot == 45)
    let wrapped = PSInteraction.rotated(s, startRot: 170, startAngle: 0, angle: 30 * .pi / 180, snap: false)
    #expect(abs(wrapped.rot - (-160)) < 1e-9)
  }
}
