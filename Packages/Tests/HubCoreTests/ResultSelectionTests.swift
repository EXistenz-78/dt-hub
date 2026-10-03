import Foundation
import Testing

@testable import HubCore

/// Which pictures of the Results strip are selected (newest first in `order`).
struct ResultSelectionTests {
  let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
  var order: [UUID] { [a, b, c, d, e] }

  @Test func aPlainClickSelectsOnlyThatPicture() {
    var selection = ResultSelection(only: a)
    selection.click(c, command: false, shift: false, order: order)
    #expect(selection.ids == [c] && selection.primary == c && selection.anchor == c)
  }

  @Test func commandAddsAndTakesAwayAndTheShownPictureFollows() {
    var selection = ResultSelection(only: a)
    selection.click(c, command: true, shift: false, order: order)
    #expect(selection.ids == [a, c] && selection.primary == c)
    selection.click(c, command: true, shift: false, order: order)
    #expect(selection.ids == [a])
    #expect(selection.primary == a, "the large picture moves to one that is still selected")
  }

  @Test func theLastSelectedPictureCannotBeTakenAway() {
    var selection = ResultSelection(only: b)
    selection.click(b, command: true, shift: false, order: order)
    #expect(selection.ids == [b] && selection.primary == b)
  }

  @Test func shiftExtendsFromTheAnchorInEitherDirection() {
    var selection = ResultSelection(only: b)
    selection.click(d, command: false, shift: true, order: order)
    #expect(selection.ids == [b, c, d] && selection.primary == d && selection.anchor == b)
    selection.click(a, command: false, shift: true, order: order)
    #expect(selection.ids == [a, b])
  }

  @Test func shiftWithoutAnAnchorIsAPlainClick() {
    var selection = ResultSelection()
    selection.click(c, command: false, shift: true, order: order)
    #expect(selection.ids == [c] && selection.anchor == c)
  }

  @Test func selectAllTakesEveryPictureAndKeepsTheShownOne() {
    var selection = ResultSelection(only: c)
    selection.selectAll(order: order)
    #expect(selection.ids == Set(order) && selection.primary == c)
  }

  @Test func afterARemovalTheNearestPictureLeftIsSelected() {
    var selection = ResultSelection(only: b)
    selection.click(c, command: true, shift: false, order: order)
    selection.afterRemoval(removed: [b, c], order: order, remaining: [a, d, e])
    #expect(selection.ids == [d] && selection.primary == d, "the one that took the place of the first removed")
    var last = ResultSelection(only: e)
    last.afterRemoval(removed: [e], order: order, remaining: [a, b, c, d])
    #expect(last.ids == [d], "removing the oldest picks the one before it")
    var all = ResultSelection(only: a)
    all.afterRemoval(removed: Set(order), order: order, remaining: [])
    #expect(all.ids.isEmpty && all.primary == nil && all.anchor == nil)
  }

  @Test func aMenuOnAPictureOutsideTheSelectionPicksNextToThatOne() {
    var selection = ResultSelection(only: a)
    selection.afterRemoval(removed: [d], order: order, remaining: [a, b, c, e])
    #expect(selection.ids == [e], "the one that took the place of d, not a neighbour of the old selection")
  }

  @Test func theSelectionKeepsOnlyWhatIsStillInTheStrip() {
    var selection = ResultSelection(only: a)
    selection.click(c, command: true, shift: false, order: order)
    selection.keepOnly(order: [a, b])
    #expect(selection.ids == [a])
    selection.keepOnly(order: [b])
    #expect(selection.ids == [b] && selection.primary == b, "nothing left selected: the first picture")
    selection.keepOnly(order: [])
    #expect(selection.ids.isEmpty && selection.primary == nil)
  }
}
