import DTHubPluginKit
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Prompt")
struct PSPromptTests {
  func state(_ description: String = "una valle di montagna al tramonto") -> PSState {
    let state = PSState(italian: false)
    state.mutate { $0.description = description }
    return state
  }

  /// An `ask` that answers from a list, in order, and records the requests.
  @MainActor final class Asker {
    var answers: [DTHubLLMAnswer]
    private(set) var requests: [(prompt: String, system: String)] = []
    init(_ answers: [DTHubLLMAnswer]) { self.answers = answers }
    func ask(_ prompt: String, _ system: String) async -> DTHubLLMAnswer {
      requests.append((prompt, system))
      return answers.isEmpty ? .failure("No answer.") : answers.removeFirst()
    }
  }

  @Test func improveReplacesOnlyTheDescription() async {
    let state = state()
    state.mutate { $0.stickers = [Sticker(name: "a", file: "a.png")]; $0.mode = .fast }
    let before = state.doc
    let asker = Asker([.text("A mountain valley at sunset, warm low light, long shadows, haze in the lower valley.")])
    await state.improve(using: asker.ask)
    #expect(state.doc.description.hasPrefix("A mountain valley at sunset"))
    #expect(state.doc.stickers == before.stickers && state.doc.mode == .fast)
    #expect(state.error == nil)
  }

  @Test func undoRestoresTheLastTextOnly() async {
    let state = state("old text")
    let asker = Asker([.text("A new English description of a quiet harbour at dawn, soft grey light.")])
    await state.improve(using: asker.ask)
    state.undoImprove()
    #expect(state.doc.description == "old text")
    state.undoImprove()
    #expect(state.doc.description == "old text")
  }

  @Test func anItalianAnswerIsRetriedOnceThenKeptOut() async {
    let italian = "Una valle di montagna con il sole che tramonta e le ombre lunghe sulla neve."
    let state = state("valley")
    let asker = Asker([.text(italian), .text("A mountain valley at sunset with long shadows on the snow, warm light.")])
    await state.improve(using: asker.ask)
    #expect(asker.requests.count == 2 && asker.requests[1].prompt.localizedCaseInsensitiveContains("English"))
    #expect(state.doc.description.hasPrefix("A mountain valley"))

    let stubborn = self.state("valley")
    let again = Asker([.text(italian), .text(italian)])
    await stubborn.improve(using: again.ask)
    #expect(stubborn.doc.description == "valley" && stubborn.error != nil)
  }

  @Test func theAnswerNeverCarriesTheTriggerPhrase() async {
    let state = state("valley")
    let asker = Asker([.text("Fill the green spaces according to the image. A valley at sunset with a warm light and long shadows.")])
    await state.improve(using: asker.ask)
    #expect(state.doc.description == "valley" && state.error != nil)
  }

  @Test func noModelGivesAReadableError() async {
    let state = state("valley")
    await state.improve(using: Asker([.failure("No language model is chosen.")]).ask)
    #expect(state.error == "No language model is chosen." && state.doc.description == "valley")
  }

  @Test func anEmptyDescriptionSendsNothing() async {
    let state = state("   ")
    let asker = Asker([.text("anything")])
    await state.improve(using: asker.ask)
    #expect(asker.requests.isEmpty && state.error != nil)
  }

  @Test func theRequestHasTheDescriptionAndNotTheTrigger() {
    let request = PSPrompt.request(description: "a quiet harbour at dawn")
    #expect(request.prompt.contains("a quiet harbour at dawn"))
    #expect(!request.prompt.localizedCaseInsensitiveContains("fill the green spaces"))
    #expect(request.system.contains("360° panorama generator"))
  }

  @Test func answersAreCleanedOfQuotesAndFences() {
    #expect(PSPrompt.clean("  \"A harbour at dawn.\"\n") == "A harbour at dawn.")
    #expect(PSPrompt.clean("```\nA harbour at dawn.\n```") == "A harbour at dawn.")
  }

  @Test func theFileAndTheBuiltInCopyAreTheSame() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Data/master-prompt.md")
    #expect(try String(contentsOf: file, encoding: .utf8) == PSEmbedded.masterPrompt + (PSEmbedded.masterPrompt.hasSuffix("\n") ? "" : "\n"))
  }

  @Test func theMasterPromptIsInstalledAndCustomTextFollowsIt() throws {
    let data = TestImages.tempFolder()
    PSPrompt.install(dataFolder: data)
    let folder = PSPrompt.folder(dataFolder: data)
    #expect(FileManager.default.fileExists(atPath: folder.folder.appendingPathComponent("master-prompt.md").path))
    try "Always mention a lighthouse.".write(to: folder.folder.appendingPathComponent("custom/master-prompt.md"), atomically: true, encoding: .utf8)
    let system = PSPrompt.system(in: folder)
    #expect(system.contains("360° panorama generator") && system.hasSuffix("Always mention a lighthouse."))
  }

  @Test func theItalianCheckSpotsItalianOnly() {
    #expect(PSPrompt.looksItalian("Una valle di montagna con il sole che tramonta sulla neve"))
    #expect(!PSPrompt.looksItalian("A mountain valley with the sun setting over the snow"))
    #expect(!PSPrompt.looksItalian("Alpine valley, golden hour, 35mm"))
  }
}
