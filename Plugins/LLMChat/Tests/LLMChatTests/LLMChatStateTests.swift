import DTHubPluginKit
import Foundation
import Testing

@testable import LLMChat

@MainActor
@Suite("LLM Chat state")
struct LLMChatStateTests {
  let withVision = #"{"name":"vl","path":"/m/vl","supportsImages":true}"#
  let textOnly = #"{"name":"txt","path":"/m/txt","supportsImages":false}"#

  func contextJSON(models: String? = nil, prompt: String? = "a cat", images: Bool = true) -> Data {
    let list = models ?? "[\(withVision),\(textOnly)]"
    var parts = [#""type":"context""#, #""tempFolder":"/t""#, #""model":"m.ckpt""#, #""family":"flux2_9b""#, #""languageModels":\#(list)"#]
    if let prompt { parts.append(#""prompt":"\#(prompt)","negativePrompt":"""#) }
    parts.append(#""parameters":{"steps":8,"sampler":0,"loras":[{"file":"x.ckpt","weight":1,"mode":0,"trigger":""}]}"#)
    if images { parts.append(#""startImage":"/tmp/start.png","moodboard":["/tmp/m1.png"],"strength":0.7"#) }
    return Data(("{" + parts.joined(separator: ",") + "}").utf8)
  }

  func state(models: String? = nil, prompt: String? = "a cat", images: Bool = true, folder: URL? = nil) -> LLMChatState {
    let s = LLMChatState(store: ChatStore(folder: folder), italian: false)
    s.apply(context: contextJSON(models: models, prompt: prompt, images: images))
    s.active = true
    return s
  }

  final class Log {
    var asked: [(prompt: String, images: [String], system: String, model: String, history: [DTHubLLMTurn])] = []
    var sent: [[String: Any]] = []
  }

  func ask(_ log: Log, reply: DTHubLLMAnswer) -> LLMChatState.Ask {
    { prompt, images, system, model, history in
      log.asked.append((prompt, images, system, model, history))
      return reply
    }
  }

  func contribute(_ log: Log, answer: [String: Any]? = ["type": "ok"]) -> LLMChatState.Contribute {
    { body in
      log.sent.append(body)
      return answer
    }
  }

  let action = "Done.\n```dthub\n{\"fields\":{\"prompt\":\"darker\",\"steps\":4}}\n```"

  @Test func aMessageWithoutTheCommandNeverSendsEvenIfTheAnswerHasABlock() async {
    let s = state()
    let log = Log()
    s.draft = "make it darker"
    await s.send(using: ask(log, reply: .text(action)), contribute: contribute(log))
    #expect(log.sent.isEmpty)
    #expect(s.chat.messages.last?.note == .ignored)
    #expect(s.chat.messages.map(\.role) == [.user, .assistant, .note])
    #expect(log.asked.first?.system.contains("Prompt: \"\"\"a cat\"\"\"") == true && log.asked.first?.model == "vl")
  }

  @Test func withTheCommandTheBlockIsSentAndTheLocalCopyFollows() async {
    let s = state()
    let log = Log()
    s.draft = "make it darker <SEND>"
    await s.send(using: ask(log, reply: .text(action)), contribute: contribute(log))
    #expect(log.sent.count == 1)
    let fields = log.sent.first?["fields"] as? [String: Any]
    #expect(fields?["prompt"] as? String == "darker" && fields?["steps"] as? Int == 4)
    let last = s.chat.messages.last
    #expect(last?.note == .action && last?.text == "Sent: prompt, steps.")
    #expect(s.context?.prompt == "darker" && s.context?.parameters?.steps == 4)
  }

  @Test func theCommandWithoutABlockSaysThereWasNoAction() async {
    let s = state()
    let log = Log()
    s.draft = "hello <SEND>"
    await s.send(using: ask(log, reply: .text("Just text.")), contribute: contribute(log))
    #expect(log.sent.isEmpty && s.chat.messages.last?.note == .ignored)
  }

  @Test func aBlockWithNothingUsableSaysSoInsteadOfNoAction() async {
    let s = state()
    let log = Log()
    s.draft = "go <SEND>"
    await s.send(using: ask(log, reply: .text("```dthub\n{\"foo\":1}\n```")), contribute: contribute(log))
    #expect(log.sent.isEmpty)
    #expect(s.chat.messages.last?.text == L.text(.nothingUsable, italian: false))
  }

  @Test func aBareListPipelineFromASmallModelIsSent() async {
    let s = state()
    let log = Log()
    s.draft = "five variants <SEND>"
    await s.send(
      using: ask(log, reply: .text("```dthub\n{\"pipeline\":[{\"fields\":{\"prompt\":\"a\"}},{\"fields\":{\"prompt\":\"b\"}}]}\n```")),
      contribute: contribute(log))
    #expect(log.sent.count == 1 && s.chat.messages.last?.note == .action)
    #expect(s.chat.messages.last?.text == "Sent: pipeline (2 passes).")
  }

  @Test func anInvalidBlockOrTooLongAPipelineIsAnErrorAndSendsNothing() async {
    let s = state()
    let log = Log()
    s.draft = "go <SEND>"
    await s.send(using: ask(log, reply: .text("```dthub\nnot json\n```")), contribute: contribute(log))
    #expect(s.chat.messages.last?.note == .error && log.sent.isEmpty)
    let steps = Array(repeating: #"{"fields":{"steps":4}}"#, count: 21).joined(separator: ",")
    s.draft = "go <SEND>"
    await s.send(
      using: ask(log, reply: .text("```dthub\n{\"fields\":{\"prompt\":\"x\"},\"pipeline\":{\"steps\":[\(steps)]}}\n```")),
      contribute: contribute(log))
    #expect(s.chat.messages.last?.note == .error && log.sent.isEmpty)
  }

  @Test func theImagesGoNumberedAndTheSavedMessageHasNoBlock() async {
    let s = state()
    let log = Log()
    s.draft = "describe image 1"
    await s.send(using: ask(log, reply: .text("ok")), contribute: contribute(log))
    #expect(log.asked.first?.images == ["/tmp/start.png", "/tmp/m1.png"])
    #expect(log.asked.first?.prompt.hasPrefix("Attached images:\n- Image 1: the start image") == true)
    #expect(log.asked.first?.prompt.hasSuffix("describe image 1") == true)
    let user = s.chat.messages.first
    #expect(user?.text == "describe image 1" && user?.images == ["start.png", "m1.png"])
  }

  @Test func theSwitchOffOrATextModelSendsNoImages() async {
    let off = state()
    off.settings.includeImages = false
    let log = Log()
    off.draft = "x"
    await off.send(using: ask(log, reply: .text("ok")), contribute: contribute(log))
    #expect(log.asked.first?.images.isEmpty == true && log.asked.first?.prompt == "x")

    let text = state()
    text.selectModel("txt")
    #expect(!text.imagesAvailable)
    let log2 = Log()
    text.draft = "x"
    await text.send(using: ask(log2, reply: .text("ok")), contribute: contribute(log2))
    #expect(log2.asked.first?.images.isEmpty == true && log2.asked.first?.model == "txt")
  }

  @Test func aFailureIsAnErrorNoteAndTheMessageStays() async {
    let s = state()
    s.draft = "hi"
    await s.send(using: ask(Log(), reply: .failure("Not enough memory")), contribute: contribute(Log()))
    #expect(s.chat.messages.map(\.role) == [.user, .note])
    #expect(s.chat.messages.last?.note == .error && s.chat.messages.last?.text == "Not enough memory")
  }

  @Test func anAppWithoutPromptsAsksForAnUpdateAndNeverCallsTheLLM() async {
    let s = state(prompt: nil)
    #expect(s.blocker == L.text(.needsNewApp, italian: false))
    let log = Log()
    s.draft = "hi"
    await s.send(using: ask(log, reply: .text("ok")), contribute: contribute(log))
    #expect(log.asked.isEmpty && s.chat.messages.isEmpty)
  }

  @Test func otherBlockers() {
    let off = LLMChatState(store: ChatStore(folder: nil), italian: false)
    #expect(off.blocker == L.text(.notActive, italian: false))
    off.active = true
    #expect(off.blocker == L.text(.waitingContext, italian: false))
    off.apply(context: contextJSON(models: "[]"))
    #expect(off.blocker == L.text(.noModels, italian: false))
  }

  @Test func stopWaitingDropsTheAnswerThatArrivesLater() async {
    let s = state()
    s.draft = "hi"
    let gate = AsyncGate()
    let log = Log()
    let task = Task {
      await s.send(
        using: { _, _, _, _, _ in
          await gate.wait()
          return .text("late")
        }, contribute: contribute(log))
    }
    for _ in 0..<200 where !s.isWaiting { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(s.isWaiting)
    s.cancelWait()
    #expect(!s.isWaiting)
    await gate.open()
    await task.value
    #expect(s.chat.messages.map(\.role) == [.user])
  }

  @Test func aProjectSwitchWhileWaitingKeepsTheAnswerOutOfBothChats() async throws {
    let dirA = FileManager.default.temporaryDirectory.appendingPathComponent("llmchat-a-\(UUID().uuidString)")
    let dirB = FileManager.default.temporaryDirectory.appendingPathComponent("llmchat-b-\(UUID().uuidString)")
    let s = state(folder: dirA)
    s.draft = "hi"
    let gate = AsyncGate()
    let task = Task {
      await s.send(
        using: { _, _, _, _, _ in
          await gate.wait()
          return .text("late")
        }, contribute: contribute(Log()))
    }
    for _ in 0..<200 where !s.isWaiting { try? await Task.sleep(for: .milliseconds(5)) }
    s.switchProject(folder: dirB)
    await gate.open()
    await task.value
    #expect(s.chat.messages.isEmpty)
    // The old project's chat stays as it was saved: the question, no answer.
    let old = ChatStore(folder: dirA)
    let saved = try #require(old.list().first.flatMap { old.load($0.id) })
    #expect(saved.messages.map(\.role) == [.user])
  }

  @Test func newChatKeepsTheOldOneAndDeleteOpensTheMostRecentLeft() async {
    let s = state()
    let log = Log()
    s.draft = "first"
    await s.send(using: ask(log, reply: .text("ok")), contribute: contribute(log))
    let first = s.chat.id
    s.newChat()
    #expect(s.chat.messages.isEmpty && s.summaries.map(\.id) == [first])
    s.draft = "second"
    await s.send(using: ask(log, reply: .text("ok")), contribute: contribute(log))
    #expect(s.summaries.count == 2)
    s.deleteCurrent()
    #expect(s.chat.id == first && s.summaries.count == 1)
    s.deleteCurrent()
    #expect(s.chat.messages.isEmpty && s.summaries.isEmpty)
  }

  @Test func settingsAreSavedWhenTheModelOrTheSwitchChange() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("llmchat-s-\(UUID().uuidString)")
    let s = state(folder: dir)
    s.selectModel("txt")
    s.settings.includeImages = false
    let saved = ChatStore(folder: dir).loadSettings()
    #expect(saved.model == "txt" && saved.includeImages == false)
  }

  @Test func theHistoryOfTheChatGoesWithTheNextMessage() async {
    let s = state()
    let log = Log()
    s.draft = "one"
    await s.send(using: ask(log, reply: .text("answer one")), contribute: contribute(log))
    s.draft = "two"
    await s.send(using: ask(log, reply: .text("answer two")), contribute: contribute(log))
    #expect(log.asked[1].history == [DTHubLLMTurn(role: .user, text: "one"), DTHubLLMTurn(role: .assistant, text: "answer one")])
  }

  @Test func theCommandButtonAddsTheCommandAtTheEnd() {
    let s = state()
    s.draft = "make it darker"
    s.insertCommand()
    #expect(s.draft == "make it darker <SEND>")
    s.draft = ""
    s.insertCommand()
    #expect(s.draft == "<SEND>")
  }

  @Test func bothLanguagesHaveEveryWord() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }
}

/// Holds an answer back until the test opens it.
actor AsyncGate {
  private var opened = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    if opened { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func open() {
    opened = true
    waiters.forEach { $0.resume() }
    waiters = []
  }
}
