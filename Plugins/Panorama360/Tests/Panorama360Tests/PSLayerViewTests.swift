import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Picture layer")
struct PSLayerViewTests {
  @Test func theLayerShowsEachNewImageAtOnce() throws {
    let box = PSPreview()
    let view = PSLayerHostView()
    view.bind(box)
    #expect(view.layer?.contents == nil)
    let first = TestImages.solid(8, 6, 1, 2, 3)
    box.image = first
    #expect((view.layer?.contents as AnyObject?) === first)
    let second = TestImages.solid(8, 6, 9, 9, 9)
    box.image = second
    #expect((view.layer?.contents as AnyObject?) === second)
    box.image = nil
    #expect(view.layer?.contents == nil)
  }

  @Test func theViewLetsThePointerThroughToTheGesturesOverIt() {
    let view = PSLayerHostView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    #expect(view.hitTest(NSPoint(x: 50, y: 50)) == nil)
  }

  @Test func rebindingToAnotherBoxFollowsTheNewOne() {
    let one = PSPreview(), two = PSPreview()
    let view = PSLayerHostView()
    view.bind(one)
    view.bind(two)
    let image = TestImages.solid(4, 4, 1, 1, 1)
    one.image = TestImages.solid(4, 4, 7, 7, 7)
    #expect(view.layer?.contents == nil, "the old box is no longer followed")
    two.image = image
    #expect((view.layer?.contents as AnyObject?) === image)
  }
}
