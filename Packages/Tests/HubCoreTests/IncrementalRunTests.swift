import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct IncrementalRunTests {
  func result() -> GeneratedImage {
    GeneratedImage(
      image: testImage(), job: GenerationJob(prompt: "p", model: "m", parameters: GenerationParameters()),
      date: Date(), fileURL: nil, saveError: nil)
  }

  func output(
    enabled: Bool = true, phase: GenerationSession.Phase = .idle, stopped: Bool = false,
    before: GeneratedImage.ID?, results: [GeneratedImage]
  ) -> GeneratedImage? {
    IncrementalRun.output(enabled: enabled, phase: phase, stopped: stopped, before: before, results: results)
  }

  @Test func offGivesNothing() {
    let old = result()
    let new = result()
    #expect(output(enabled: false, before: old.id, results: [new, old]) == nil)
  }

  @Test func aFailedRunGivesNothingEvenAfterAGoodBatch() {
    let old = result()
    let new = result()
    #expect(output(phase: .failed(.generationFailed("x")), before: old.id, results: [new, old]) == nil)
  }

  @Test func aStoppedRunGivesNothingEvenWithNewImages() {
    let old = result()
    let new = result()
    #expect(output(stopped: true, before: old.id, results: [new, old]) == nil)
  }

  @Test func noNewImageGivesNothing() {
    let old = result()
    #expect(output(before: old.id, results: [old]) == nil)
    #expect(output(before: nil, results: []) == nil)
  }

  @Test func theNewestImageIsTheOne() {
    let old = result()
    let a = result()
    let b = result()
    #expect(output(before: old.id, results: [b, a, old])?.id == b.id)
    #expect(output(before: nil, results: [a])?.id == a.id)
  }
}
