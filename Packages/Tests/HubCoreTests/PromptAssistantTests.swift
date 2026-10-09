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
  static let fakeModel = LanguageModelDescriptor(path: "/m/fake", name: "fake", sizeBytes: 1, supportsImages: true)

  init() {
    let recorder = recorder
    assistant = PromptAssistant(
      resolve: { _, _, _ in .success(.init(model: Self.fakeModel, profile: LanguageModelProfile())) },
      respond: { prompt, images, options, _ throws(LanguageModelError) in
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

@MainActor
struct PromptAssistantChoiceTests {
  let model = LanguageModelDescriptor(path: "/m/pe", name: "pe", sizeBytes: 1, supportsImages: true)

  final class Log {
    var asked: [(LanguageModelTask, String?)] = []
    var calls: [(String, LanguageModelOptions, String)] = []
  }

  func assistant(_ profile: LanguageModelProfile, resolveFails: LanguageModelError? = nil, log: Log) -> PromptAssistant {
    let model = model
    return PromptAssistant(
      resolve: { task, family, _ in
        log.asked.append((task, family))
        if let resolveFails { return .failure(resolveFails) }
        return .success(.init(model: model, profile: profile))
      },
      respond: { prompt, _, options, chosen throws(LanguageModelError) in
        log.calls.append((prompt, options, chosen.name))
        return "A cat."
      })
  }

  @Test func noOwnSystemPromptMeansTheUsualRequest() async {
    let log = Log()
    let a = assistant(LanguageModelProfile(), log: log)
    let current = PromptPair(prompt: "gatto", negative: "")
    _ = await a.enhance(current, family: "flux2")
    #expect(log.calls.first?.0 == PromptBrief.enhance(current, family: "flux2").prompt)
    #expect(log.calls.first?.1 == PromptBrief.enhance(current, family: "flux2").options)
    #expect(log.calls.first?.2 == "pe")
    #expect(log.asked.first?.0 == .enhance && log.asked.first?.1 == "flux2")
  }

  @Test func anOwnSystemPromptSendsTheTextAsItIs() async {
    let log = Log()
    let profile = LanguageModelProfile(
      generation: .init(temperature: 0.7), enhancePrompt: "PE rules", describePrompt: "PE rules")
    let a = assistant(profile, log: log)
    let current = PromptPair(prompt: "gatto", negative: "")
    _ = await a.enhance(current, family: "qwen_image_2.1")
    #expect(log.calls.first?.0 == "gatto")
    #expect(log.calls.first?.1 == PromptBrief.enhance(current, ownSystem: "PE rules", generation: profile.generation).options)
    #expect(log.calls.first?.1.thinking == true)
  }

  @Test func aFailedChoiceNeverCallsTheModel() async {
    let log = Log()
    let a = assistant(LanguageModelProfile(), resolveFails: .noModelSelected, log: log)
    let result = await a.enhance(PromptPair(prompt: "x", negative: ""), family: "flux2")
    #expect(result == nil)
    #expect(a.failure == .model(.noModelSelected))
    #expect(log.calls.isEmpty)
  }
}

@MainActor
struct PromptAssistantImagesTests {
  let model = LanguageModelDescriptor(path: "/m/vl", name: "vl", sizeBytes: 1, supportsImages: true)
  let a = URL(fileURLWithPath: "/tmp/a.png")
  let b = URL(fileURLWithPath: "/tmp/b.png")
  let current = PromptPair(prompt: "cat from image 2 on image 1", negative: "")

  final class Log {
    var resolves: [(LanguageModelTask, Bool)] = []
    var calls: [(String, [URL])] = []
  }

  /// `noVisionFor`: the `needsImages` value for which the resolver answers "no LLM reads images".
  func needsSeen(_ task: LanguageModelTask, images: EnhanceImages, describe: Bool = false) async -> [LanguageModelNeeds] {
    var seen: [LanguageModelNeeds] = []
    let model = model
    let a1 = PromptAssistant(
      resolve: { _, _, needs in
        seen.append(needs)
        if needs.needsImages, !describe { return .failure(.imagesNotSupported) }
        return .success(.init(model: model, profile: LanguageModelProfile()))
      },
      respond: { _, _, _, _ throws(LanguageModelError) in "ok" })
    if describe {
      _ = await a1.describe(imageAt: a, current: current, family: "flux2")
    } else {
      _ = await a1.enhance(current, family: "flux2", images: images)
    }
    return seen
  }

  @Test func theControlContextTravelsWithTheRequest() async {
    #expect(await needsSeen(.enhance, images: EnhanceImages()) == [LanguageModelNeeds(controlHasImages: false, needsImages: false)])
    #expect(
      await needsSeen(.enhance, images: EnhanceImages(start: a)) == [
        LanguageModelNeeds(controlHasImages: true, needsImages: true),
        LanguageModelNeeds(controlHasImages: true, needsImages: false),
      ])
    #expect(
      await needsSeen(.describe, images: EnhanceImages(), describe: true) == [
        LanguageModelNeeds(controlHasImages: true, needsImages: true)
      ])
  }

  func assistant(
    _ log: Log, profile: LanguageModelProfile = LanguageModelProfile(), failWithImages: LanguageModelError? = nil
  ) -> PromptAssistant {
    let model = model
    return PromptAssistant(
      resolve: { task, _, needs in
        log.resolves.append((task, needs.needsImages))
        if needs.needsImages, let failWithImages { return .failure(failWithImages) }
        return .success(.init(model: model, profile: profile))
      },
      respond: { prompt, images, _, _ throws(LanguageModelError) in
        log.calls.append((prompt, images))
        return "A better prompt."
      })
  }

  @Test func pictureSendsThemInOrderAndAsksForAnLLMThatReadsThem() async {
    let log = Log()
    let images = EnhanceImages(start: a, references: [b])
    let result = await assistant(log).enhance(current, family: "flux2", images: images)
    #expect(result?.prompt == "A better prompt.")
    #expect(log.resolves.first?.1 == true)
    #expect(log.calls.first?.1 == [a, b])
    #expect(log.calls.first?.0 == PromptBrief.enhance(current, family: "flux2", images: images).prompt)
  }

  @Test func noLLMThatReadsImagesFallsBackToTheTextWithANote() async {
    let log = Log()
    let a1 = assistant(log, failWithImages: .imagesNotSupported)
    let result = await a1.enhance(current, family: "flux2", images: EnhanceImages(start: a))
    #expect(result?.prompt == "A better prompt.")
    #expect(a1.failure == nil && a1.note == .imagesNotSent)
    #expect(log.resolves.map(\.1) == [true, false])
    #expect(log.calls.first?.1.isEmpty == true)
    #expect(log.calls.first?.0 == PromptBrief.enhance(current, family: "flux2").prompt)
  }

  @Test func theNoteClearsOnTheNextOperation() async {
    let log = Log()
    let a1 = assistant(log, failWithImages: .imagesNotSupported)
    _ = await a1.enhance(current, family: "flux2", images: EnhanceImages(start: a))
    #expect(a1.note == .imagesNotSent)
    _ = await a1.enhance(current, family: "flux2")
    #expect(a1.note == nil)
  }

  @Test func noModelSelectedStaysAFailureWithoutFallback() async {
    let log = Log()
    let a1 = assistant(log, failWithImages: .noModelSelected)
    let result = await a1.enhance(current, family: "flux2", images: EnhanceImages(start: a))
    #expect(result == nil && a1.failure == .model(.noModelSelected) && a1.note == nil)
    #expect(log.resolves.map(\.1) == [true])
    #expect(log.calls.isEmpty)
  }

  @Test func withoutPicturesNothingChanges() async {
    let log = Log()
    _ = await assistant(log).enhance(current, family: "flux2")
    #expect(log.resolves.map(\.1) == [false])
    #expect(log.calls.first?.0 == PromptBrief.enhance(current, family: "flux2").prompt)
    #expect(log.calls.first?.1.isEmpty == true)
  }

  @Test func anOwnImageToImagePromptIsUsedWithPictures() async {
    let log = Log()
    let profile = LanguageModelProfile(enhancePrompt: "T2I RULES", describePrompt: "I2I RULES", enhanceWithImagesPrompt: "I2I RULES")
    let images = EnhanceImages(start: a)
    _ = await assistant(log, profile: profile).enhance(current, family: "qwen_image_2.1", images: images)
    #expect(log.calls.first?.0 == PromptBrief.enhance(current, ownSystem: "I2I RULES", generation: nil, images: images).prompt)
  }
}
