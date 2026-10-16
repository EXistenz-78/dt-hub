import Foundation
import Testing

@testable import HubCore

struct ResultsAttentionTests {
  let first = UUID()
  let second = UUID()

  @Test func atLaunchWithOldResultsNothingIsToBeSeen() {
    let attention = ResultsAttention(lastSeen: first)
    #expect(attention.state(isBusy: false, newestResultID: first, windowVisible: false) == .idle)
  }

  @Test func whileARunWorksItIsWorkingWhateverTheWindowSays() {
    let attention = ResultsAttention(lastSeen: first)
    #expect(attention.state(isBusy: true, newestResultID: first, windowVisible: false) == .working)
    #expect(attention.state(isBusy: true, newestResultID: second, windowVisible: true) == .working)
  }

  @Test func aNewImageWithTheWindowClosedIsToBeSeen() {
    let attention = ResultsAttention(lastSeen: first)
    #expect(attention.state(isBusy: false, newestResultID: second, windowVisible: false) == .unseen)
  }

  @Test func aRunStoppedAfterProducingAnImageIsToBeSeen() {
    // Stop ends the run like any other end: what counts is whether a new image is there.
    let attention = ResultsAttention(lastSeen: nil)
    #expect(attention.state(isBusy: false, newestResultID: first, windowVisible: false) == .unseen)
  }

  @Test func aRunWithoutANewImageLeavesNothingToBeSeen() {
    let attention = ResultsAttention(lastSeen: first)
    #expect(attention.state(isBusy: false, newestResultID: first, windowVisible: false) == .idle)
  }

  @Test func aVisibleWindowMeansTheImagesAreSeen() {
    var attention = ResultsAttention(lastSeen: first)
    #expect(attention.state(isBusy: false, newestResultID: second, windowVisible: true) == .idle)
    attention.update(newestResultID: second, windowVisible: true)
    // The window is closed afterwards: the image was seen while it was open.
    #expect(attention.state(isBusy: false, newestResultID: second, windowVisible: false) == .idle)
  }

  @Test func openingTheWindowClearsTheMark() {
    var attention = ResultsAttention(lastSeen: first)
    #expect(attention.state(isBusy: false, newestResultID: second, windowVisible: false) == .unseen)
    attention.update(newestResultID: second, windowVisible: true)
    #expect(attention.state(isBusy: false, newestResultID: second, windowVisible: true) == .idle)
  }

  @Test func updatingWithTheWindowClosedChangesNothing() {
    var attention = ResultsAttention(lastSeen: first)
    attention.update(newestResultID: second, windowVisible: false)
    #expect(attention.lastSeen == first)
  }

  @Test func clearedResultsAreNothingToSee() {
    let attention = ResultsAttention(lastSeen: first)
    #expect(attention.state(isBusy: false, newestResultID: nil, windowVisible: false) == .idle)
  }
}
