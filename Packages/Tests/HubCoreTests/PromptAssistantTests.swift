import Foundation
import HubKit
import Testing

@testable import HubCore

/// Stands in for the language model: records the calls, answers or throws what the test says.
@MainActor
final class PromptRecorder {
  struct Call: Equatable {
    var prompt: String
    var images: [URL]
    var options: LanguageModelOptions
  }

  var calls: [Call] = []
  var result: Result<String, LanguageModelError> = .success("")
  /// When true the next call waits until `release()`.
  var suspends = false
  private var gate: CheckedContinuation<Void, Never>?

  func respond(_ prompt: String, _ images: [URL], _ options: LanguageModelOptions) async throws(
    LanguageModelError
  ) -> String {
    calls.append(Call(prompt: prompt, images: images, options: options))
    if suspends {
      await withCheckedContinuation { gate = $0 }
    }
    return try result.get()
  }

  func release() {
    gate?.resume()
    gate = nil
  }
}

@MainActor
struct PromptAssistantTests {
  let recorder = PromptRecorder()
  let assistant: PromptAssistant

  init() {
    let recorder = recorder
    assistant = PromptAssistant(respond: { prompt, images, options throws(LanguageModelError) in
      try await recorder.respond(prompt, images, options)
    })
  }

  @Test func enhanceWritesTheAnswerAndKeepsTheNegativeWhenTheFamilyHasNone() async {
    recorder.result = .success("A cat, detailed.")
    let current = PromptPair(prompt: "gatto", negative: "old neg")
    let result = await assistant.enhance(current, family: "flux2")
    #expect(result == PromptPair(prompt: "A cat, detailed.", negative: "old neg"))
    let expected = PromptBrief.enhance(current, family: "flux2")
    #expect(recorder.calls == [.init(prompt: expected.prompt, images: expected.images, options: expected.options)])
  }

  @Test func enhanceFillsTheNegativeForAFamilyThatUsesIt() async {
    recorder.result = .success("{\"prompt\":\"a cat\",\"negative\":\"blurry\"}")
    let result = await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "v1")
    #expect(result == PromptPair(prompt: "a cat", negative: "blurry"))
  }

  @Test func aNegativeFamilyWhoseAnswerHasNoNegativeKeepsTheOldOne() async {
    recorder.result = .success("a cat")
    let result = await assistant.enhance(PromptPair(prompt: "gatto", negative: "old"), family: "v1")
    #expect(result == PromptPair(prompt: "a cat", negative: "old"))
  }

  @Test func aFamilyWithoutNegativeIgnoresTheNegativeOfTheAnswer() async {
    recorder.result = .success("{\"prompt\":\"a cat\",\"negative\":\"blurry\"}")
    let result = await assistant.enhance(PromptPair(prompt: "gatto", negative: "old"), family: "flux2")
    #expect(result == PromptPair(prompt: "a cat", negative: "old"))
  }

  @Test func emptyPromptDoesNotCallTheModel() async {
    let result = await assistant.enhance(PromptPair(prompt: "   \n", negative: "x"), family: "flux2")
    #expect(result == nil)
    #expect(assistant.failure == .emptyPrompt)
    #expect(recorder.calls.isEmpty)
    #expect(assistant.working == nil)
  }

  @Test func unknownFamilyWorksInProse() async {
    recorder.result = .success("A cat")
    for family in [nil, "mystery"] as [String?] {
      let result = await assistant.enhance(PromptPair(prompt: "gatto", negative: "neg"), family: family)
      #expect(result == PromptPair(prompt: "A cat", negative: "neg"))
      #expect(recorder.calls.last?.options.system == PromptBrief.system(family: nil))
    }
  }

  @Test func describeNeedsAnImage() async {
    let result = await assistant.describe(imageAt: nil, current: PromptPair(prompt: "", negative: ""), family: "flux2")
    #expect(result == nil)
    #expect(assistant.failure == .noImage)
    #expect(recorder.calls.isEmpty)
  }

  @Test func describeSendsTheImage() async {
    let url = URL(fileURLWithPath: "/tmp/a.png")
    recorder.result = .success("{\"prompt\":\"a cat\",\"negative\":\"blurry\"}")
    let result = await assistant.describe(imageAt: url, current: PromptPair(prompt: "old", negative: ""), family: "krea_2")
    #expect(recorder.calls.first?.images == [url])
    #expect(result == PromptPair(prompt: "a cat", negative: "blurry"))
  }

  @Test func serviceErrorsAreReported() async {
    recorder.result = .failure(.noModelSelected)
    let result = await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2")
    #expect(result == nil)
    #expect(assistant.failure == .model(.noModelSelected))
    #expect(assistant.working == nil)
  }

  @Test func emptyAnswerIsReported() async {
    recorder.result = .success("<think>x")
    let result = await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2")
    #expect(result == nil)
    #expect(assistant.failure == .emptyAnswer)
  }

  @Test func oneOperationAtATime() async {
    recorder.result = .success("A cat")
    recorder.suspends = true
    let first = Task { await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2") }
    while recorder.calls.isEmpty { await Task.yield() }
    #expect(assistant.working == .enhance)
    let second = await assistant.enhance(PromptPair(prompt: "cane", negative: ""), family: "flux2")
    #expect(second == nil)
    #expect(recorder.calls.count == 1)
    recorder.release()
    let result = await first.value
    #expect(result?.prompt == "A cat")
    #expect(assistant.working == nil)
  }

  @Test func aNewOperationClearsTheFailure() async {
    recorder.result = .failure(.noModelSelected)
    _ = await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2")
    #expect(assistant.failure != nil)
    recorder.result = .success("A cat")
    _ = await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2")
    #expect(assistant.failure == nil)
  }

  @Test func undoOfferedUntilTheFieldsChange() async {
    recorder.result = .success("A cat")
    _ = await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2")
    #expect(assistant.undoOffer(current: PromptPair(prompt: "A cat", negative: "")) == PromptPair(prompt: "gatto", negative: ""))
    #expect(assistant.undoOffer(current: PromptPair(prompt: "A cat!", negative: "")) == nil)
    assistant.clearUndo()
    #expect(assistant.undoOffer(current: PromptPair(prompt: "A cat", negative: "")) == nil)
  }

  @Test func undoRestoresTheTextPassedToTheCallNotWhatWasTypedAfter() async {
    recorder.result = .success("A cat")
    recorder.suspends = true
    let first = Task { await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2") }
    while recorder.calls.isEmpty { await Task.yield() }
    // The user types while the model answers; the caller still asked about "gatto".
    recorder.release()
    _ = await first.value
    #expect(assistant.undoOffer(current: PromptPair(prompt: "A cat", negative: ""))?.prompt == "gatto")
  }

  @Test func aFailedOperationKeepsThePreviousUndo() async {
    recorder.result = .success("A cat")
    _ = await assistant.enhance(PromptPair(prompt: "gatto", negative: ""), family: "flux2")
    recorder.result = .failure(.generationFailed("boom"))
    _ = await assistant.enhance(PromptPair(prompt: "A cat", negative: ""), family: "flux2")
    #expect(assistant.undoOffer(current: PromptPair(prompt: "A cat", negative: "")) == PromptPair(prompt: "gatto", negative: ""))
  }
}
