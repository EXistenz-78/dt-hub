import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Panorama360

@MainActor
@Suite("Canvas")
struct PSCanvasTests {
  let canvas = CGSize(width: 1024, height: 512)

  /// A state with stickers (60° wide, 3:2 pictures) at these yaws.
  func state(yaws: [Double]) -> PSState {
    let state = PSState()
    for yaw in yaws {
      let sticker = Sticker(name: "s\(state.doc.stickers.count)", file: "s.png", yaw: yaw)
      state.mutate { $0.stickers.append(sticker) }
      state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: sticker.id)
    }
    state.select(state.doc.stickers.last?.id)
    return state
  }

  func uv(lon: Double, lat: Double = 0) -> PSUV { (u: lon / 360 + 0.5, v: 0.5 - lat / 180) }
  func px(_ p: PSUV) -> CGPoint { CGPoint(x: p.u * canvas.width, y: p.v * canvas.height) }
  func uv(_ p: CGPoint) -> PSUV { (u: Double(p.x / canvas.width), v: Double(p.y / canvas.height)) }

  @Test func dragMovesTheSelectedStickerKeepingTheGrab() {
    let state = state(yaws: [0])
    state.pointerDown(at: uv(lon: 10), canvas: canvas)
    state.pointerDragged(to: uv(lon: 25), canvas: canvas, shift: false)
    state.pointerUp()
    #expect(abs(state.doc.stickers[0].yaw - 15) < 1e-9)
  }

  @Test func clickingAnotherStickerSelectsTheTopmostUnderThePointer() {
    let state = state(yaws: [0, 20, 100])
    let ids = state.doc.stickers.map(\.id)
    state.pointerDown(at: uv(lon: 10), canvas: canvas)  // under the first and the second: the second is on top
    state.pointerUp()
    #expect(state.doc.selectedID == ids[1])
  }

  @Test func clickOnEmptyCanvasKeepsTheSelectionAndMovesNothing() {
    let state = state(yaws: [0, 100])
    let before = state.doc
    state.pointerDown(at: uv(lon: -150), canvas: canvas)
    state.pointerDragged(to: uv(lon: -100), canvas: canvas, shift: false)
    state.pointerUp()
    #expect(state.doc == before)
  }

  @Test func dragFromACornerScalesTheFOV() {
    let state = state(yaws: [0])
    let sticker = state.doc.stickers[0]
    let handles = PSProjection.handles(of: sticker, aspect: 1.5)
    let centre = px(handles.center), corner = px(handles.corners[1])
    state.pointerDown(at: uv(corner), canvas: canvas)
    let doubled = CGPoint(x: centre.x + (corner.x - centre.x) * 2, y: centre.y + (corner.y - centre.y) * 2)
    state.pointerDragged(to: uv(doubled), canvas: canvas, shift: false)
    state.pointerUp()
    #expect(abs(state.doc.stickers[0].hfov - 120) < 1e-6)
  }

  @Test func dragFromTheRotateHandleRotatesAndShiftSnaps() {
    let state = state(yaws: [0])
    let handles = PSProjection.handles(of: state.doc.stickers[0], aspect: 1.5)
    let centre = px(handles.center), handle = px(handles.rotate)
    func at(_ degrees: Double) -> PSUV {
      let a = (-90 + degrees) * .pi / 180
      return uv(CGPoint(x: centre.x + 100 * cos(a), y: centre.y + 100 * sin(a)))
    }
    state.pointerDown(at: uv(handle), canvas: canvas)
    state.pointerDragged(to: at(20), canvas: canvas, shift: false)
    #expect(abs(state.doc.stickers[0].rot - 20) < 0.5)
    state.pointerDragged(to: at(30), canvas: canvas, shift: true)
    #expect(state.doc.stickers[0].rot == 45)
    state.pointerUp()
  }

  @Test func arrowsNudgeByTheStepGiven() {
    let state = state(yaws: [0])
    state.nudge(yaw: 1, pitch: 0)
    state.nudge(yaw: 0, pitch: -5)
    #expect(state.doc.stickers[0].yaw == 1 && state.doc.stickers[0].pitch == -5)
    state.nudge(yaw: 0, pitch: -100)
    #expect(state.doc.stickers[0].pitch == -89)
  }

  @Test func deleteSelectsTheNeighbour() {
    let state = state(yaws: [0, 50, 100])
    let ids = state.doc.stickers.map(\.id)
    state.select(ids[1])
    state.deleteSelected()
    #expect(state.doc.stickers.map(\.id) == [ids[0], ids[2]] && state.doc.selectedID == ids[0])
    state.deleteSelected()
    #expect(state.doc.stickers.map(\.id) == [ids[2]] && state.doc.selectedID == ids[2])
    state.deleteSelected()
    #expect(state.doc.stickers.isEmpty && state.doc.selectedID == nil)
  }

  @Test func duplicateCopiesAndShiftsYawBy10() {
    let state = state(yaws: [175, 50])
    let first = state.doc.stickers[0]
    state.select(first.id)
    state.duplicateSelected()
    #expect(state.doc.stickers.count == 3)
    let copy = state.doc.stickers[1]
    #expect(copy.id != first.id && copy.file == first.file && copy.hfov == first.hfov)
    #expect(abs(copy.yaw - (-175)) < 1e-9)
    #expect(state.doc.selectedID == copy.id && state.image(for: copy) != nil)
  }

  @Test func clearAllEmptiesTheCanvas() {
    let state = state(yaws: [0, 50])
    state.clearAll()
    #expect(state.doc.stickers.isEmpty && state.doc.selectedID == nil)
  }

  @Test func aFieldReadsTheCurrentStateEvenWithAStaleCopy() {
    let state = state(yaws: [0])
    let id = state.doc.stickers[0].id
    let stale = state.doc.stickers[0]
    let yaw = state.binding(id, \.yaw)
    state.update(id) { $0.yaw = 50 }
    #expect(stale.yaw == 0 && yaw.wrappedValue == 50)
    yaw.wrappedValue = 60
    #expect(state.sticker(id)?.yaw == 60)
  }

  @Test func theRenderedERPIs2048By1024() throws {
    let state = state(yaws: [0, 120])
    let image = try state.renderedERP(width: 2048, height: 1024)
    #expect(image.width == 2048 && image.height == 1024)
    // The first sticker is at the centre, in red.
    let centre = TestImages.pixel(image, 1024, 512)
    #expect(centre.r > 150 && centre.g < 100)
    #expect(TestImages.pixel(image, 20, 20).g == 255)
  }

  @Test func hiddenStickersAreLeftOutOfTheERP() throws {
    let state = state(yaws: [0])
    let id = state.doc.stickers[0].id
    state.update(id) { $0.visible = false }
    let image = try state.renderedERP(width: 256, height: 128)
    #expect(TestImages.pixel(image, 128, 64).g == 255)
  }
}
