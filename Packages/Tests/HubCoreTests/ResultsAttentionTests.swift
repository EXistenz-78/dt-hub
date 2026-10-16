import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ResultsAttentionTests {
  let early = Date(timeIntervalSince1970: 1_000)
  let late = Date(timeIntervalSince1970: 2_000)

  func result(date: Date, restored: Bool = false) -> GeneratedImage {
    var image = GeneratedImage(
      image: testImage(), job: GenerationJob(prompt: "p", model: "m", parameters: GenerationParameters()),
      date: date, fileURL: nil, saveError: nil)
    image.isRestored = restored
    return image
  }

  @Test func atLaunchThereIsNothingToSee() {
    let attention = ResultsAttention()
    #expect(attention.state(isBusy: false, newestDate: nil, windowVisible: false) == .idle)
  }

  @Test func whileARunWorksItIsWorkingWhateverTheWindowSays() {
    let attention = ResultsAttention(lastSeen: early)
    #expect(attention.state(isBusy: true, newestDate: early, windowVisible: false) == .working)
    #expect(attention.state(isBusy: true, newestDate: late, windowVisible: true) == .working)
  }

  @Test func theFirstImageOfTheSessionWithTheWindowClosedIsToBeSeen() {
    #expect(ResultsAttention().state(isBusy: false, newestDate: early, windowVisible: false) == .unseen)
  }

  @Test func aNewerImageWithTheWindowClosedIsToBeSeen() {
    let attention = ResultsAttention(lastSeen: early)
    #expect(attention.state(isBusy: false, newestDate: late, windowVisible: false) == .unseen)
  }

  @Test func theSameOrAnOlderNewestImageIsNothingNew() {
    // Deleting the newest image makes an older one the newest: that is not a new image.
    let attention = ResultsAttention(lastSeen: late)
    #expect(attention.state(isBusy: false, newestDate: late, windowVisible: false) == .idle)
    #expect(attention.state(isBusy: false, newestDate: early, windowVisible: false) == .idle)
  }

  @Test func aVisibleWindowMeansTheImagesAreSeen() {
    var attention = ResultsAttention(lastSeen: early)
    #expect(attention.state(isBusy: false, newestDate: late, windowVisible: true) == .idle)
    attention.update(newestDate: late, windowVisible: true)
    // The window is closed afterwards: the image was seen while it was open.
    #expect(attention.state(isBusy: false, newestDate: late, windowVisible: false) == .idle)
  }

  @Test func updatingWithTheWindowClosedChangesNothing() {
    var attention = ResultsAttention(lastSeen: early)
    attention.update(newestDate: late, windowVisible: false)
    #expect(attention.lastSeen == early)
  }

  @Test func clearedResultsAreNothingToSee() {
    let attention = ResultsAttention(lastSeen: early)
    #expect(attention.state(isBusy: false, newestDate: nil, windowVisible: false) == .idle)
  }

  // MARK: Restored images do not count

  @Test func imagesReadBackFromDiskAreNotNew() {
    // At launch and at a project switch the history comes back after the button exists: that is not a RUN.
    #expect(ResultsAttention.newestDate(in: [result(date: late, restored: true), result(date: early, restored: true)]) == nil)
    #expect(ResultsAttention.newestDate(in: []) == nil)
  }

  @Test func theNewestImageOfTheSessionIsTheFirstThatIsNotRestored() {
    let results = [result(date: late), result(date: early), result(date: early, restored: true)]
    #expect(ResultsAttention.newestDate(in: results) == late)
  }

  @Test func restoredHistoryArrivingWithTheWindowClosedLeavesTheButtonIdle() {
    let attention = ResultsAttention()
    let restored = [result(date: late, restored: true)]
    let newest = ResultsAttention.newestDate(in: restored)
    #expect(attention.state(isBusy: false, newestDate: newest, windowVisible: false) == .idle)
  }
}
