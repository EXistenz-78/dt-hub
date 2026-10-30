import CoreGraphics
import Foundation
import Testing

@testable import HubCore

/// The arrow keys of the Results window and the zoom of the large picture.
struct ResultsNavigationTests {
  let a = UUID(), b = UUID(), c = UUID()
  var order: [UUID] { [a, b, c] }

  // MARK: Arrow keys

  @Test func stepMovesToTheNeighbourAndSelectsOnlyIt() {
    var selection = ResultSelection(only: a)
    selection.click(c, command: true, shift: false, order: order)  // a and c, primary c
    selection.step(-1, order: order)
    #expect(selection.ids == [b] && selection.primary == b && selection.anchor == b)
    selection.step(1, order: order)
    #expect(selection.ids == [c])
  }

  @Test func stepStopsAtTheEnds() {
    var selection = ResultSelection(only: a)
    selection.step(-1, order: order)
    #expect(selection.primary == a)
    selection = ResultSelection(only: c)
    selection.step(1, order: order)
    #expect(selection.primary == c)
  }

  @Test func stepWithNothingSelectedPicksTheFirst() {
    var selection = ResultSelection()
    selection.step(1, order: order)
    #expect(selection.primary == a)
    var empty = ResultSelection()
    empty.step(1, order: [])
    #expect(empty.primary == nil)
  }

  // MARK: Zoom

  let view = CGSize(width: 400, height: 300)
  let fitted = CGSize(width: 400, height: 200)

  @Test func zoomNeverGoesBelowFitAndIsCappedAtEight() {
    var zoom = ResultZoom()
    zoom.zoom(by: 0.5, at: .zero, view: view, fitted: fitted)
    #expect(zoom.scale == 1 && zoom.offset == .zero)
    zoom.zoom(by: 100, at: .zero, view: view, fitted: fitted)
    #expect(zoom.scale == 8)
  }

  @Test func zoomKeepsThePointUnderTheCursorStill() {
    var zoom = ResultZoom()
    let p = CGPoint(x: 100, y: 50)  // from the centre of the view
    zoom.zoom(by: 2, at: p, view: view, fitted: fitted)
    // the image point under p before: p; after: p = offset + scale * q  with q = p
    #expect(abs(zoom.offset.x - (p.x - 2 * p.x)) < 0.001)
    #expect(abs(zoom.offset.y - (p.y - 2 * p.y)) < 0.001)
  }

  @Test func panIsLimitedSoTheImageNeverLeavesTheView() {
    var zoom = ResultZoom()
    zoom.zoom(by: 2, at: .zero, view: view, fitted: fitted)
    zoom.pan(by: CGSize(width: 10_000, height: 10_000), view: view, fitted: fitted)
    // horizontally the picture is 800 wide in a 400 view: 200 each way; vertically 400 in 300: 50.
    #expect(zoom.offset == CGPoint(x: 200, y: 50))
  }

  @Test func anAxisThatStillFitsStaysCentred() {
    var zoom = ResultZoom()
    zoom.zoom(by: 1.2, at: .zero, view: view, fitted: fitted)  // 240 high in a 300 view
    zoom.pan(by: CGSize(width: 0, height: 80), view: view, fitted: fitted)
    #expect(zoom.offset.y == 0)
  }

  @Test func resetGoesBackToFit() {
    var zoom = ResultZoom()
    zoom.zoom(by: 3, at: CGPoint(x: 30, y: 30), view: view, fitted: fitted)
    zoom.reset()
    #expect(zoom == ResultZoom())
  }
}
