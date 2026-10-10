import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PluginRoutingTests {
  let root = PluginFixture.folder()
  let target = FakeContributionTarget()

  func started(_ ids: [String] = ["a"]) throws -> (PluginRegistry, FakeLoader) {
    for id in ids { try PluginFixture.bundle(in: root, id: id, name: id.uppercased()) }
    let settingsFile = root.deletingLastPathComponent().appendingPathComponent("routing-\(root.lastPathComponent).json")
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(Set(ids))
    let loader = FakeLoader()
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    registry.contributions.target = target
    registry.start()
    return (registry, loader)
  }

  private func send(_ json: String, from id: String = "a", through loader: FakeLoader) async throws -> [String: Any] {
    let reply = await (try #require(loader.host)).receive(Data(json.utf8), from: id)
    return try #require(try JSONSerialization.jsonObject(with: reply) as? [String: Any])
  }

  @Test func aContributionFromAnActivePluginReachesTheTab() async throws {
    let (registry, loader) = try started()
    let reply = try await send(#"{"type":"contribute","fields":{"steps":4},"loras":[{"file":"x.ckpt"}]}"#, through: loader)
    #expect(reply["type"] as? String == "ok")
    #expect(reply["conflicts"] as? Int == 0)
    #expect(target.fields.parameters.steps == 4)
    #expect(registry.contributions.marks[.steps]?.pluginID == "a")
    #expect(target.loraFiles == ["x.ckpt"])
  }

  @Test func aPluginThatIsNotActiveContributesNothing() async throws {
    let (registry, loader) = try started()
    registry.setActive("a", false)
    let reply = try await send(#"{"type":"contribute","fields":{"steps":4}}"#, through: loader)
    #expect(reply["type"] as? String == "error")
    #expect(target.fields.parameters.steps != 4)
  }

  @Test func anEmptyContributionIsFineAndChangesNothing() async throws {
    let (registry, loader) = try started()
    let reply = try await send(#"{"type":"contribute","fields":{"model":"x.ckpt","steps":"four"}}"#, through: loader)
    #expect(reply["type"] as? String == "ok")
    #expect(registry.contributions.marks.isEmpty)
    #expect(target.fields == GenerationFields())
  }

  @Test func theAnswerCountsTheConflictsAndNamesWhatCouldNotBeRead() async throws {
    let (_, loader) = try started(["a", "b"])
    _ = try await send(#"{"type":"contribute","fields":{"steps":4}}"#, from: "a", through: loader)
    target.failImages = true
    let reply = try await send(#"{"type":"contribute","fields":{"steps":9},"moodboard":[{"path":"/tmp/x.png"}]}"#, from: "b", through: loader)
    #expect(reply["conflicts"] as? Int == 1)
    #expect((reply["problems"] as? [String])?.count == 1)
  }

  @Test func turningAPluginOffFromTheHeaderTakesItsMarks() async throws {
    let (registry, loader) = try started()
    _ = try await send(#"{"type":"contribute","fields":{"steps":4}}"#, through: loader)
    registry.setActive("a", false)
    #expect(registry.contributions.marks.isEmpty)
    #expect(target.fields.parameters.steps == 4)
  }

  @Test func aQuestionForTheLanguageModelIsAnswered() async throws {
    let (registry, loader) = try started()
    var asked: (String, [URL])?
    registry.askLanguageModel = { prompt, images, _, _, _ in
      asked = (prompt, images)
      return "Sunny."
    }
    let reply = try await send(#"{"type":"llm","prompt":"weather?","images":["/tmp/a.png"]}"#, through: loader)
    #expect(reply["type"] as? String == "llm")
    #expect(reply["text"] as? String == "Sunny.")
    #expect(asked?.0 == "weather?")
    #expect(asked?.1 == [URL(fileURLWithPath: "/tmp/a.png")])
  }

  @Test func theEarlierTurnsOfAChatReachTheLanguageModelInOrder() async throws {
    let (registry, loader) = try started()
    var history: [LanguageModelTurn]?
    registry.askLanguageModel = { _, _, _, _, turns in
      history = turns
      return "ok"
    }
    _ = try await send(
      #"{"type":"llm","prompt":"now","messages":[{"role":"user","text":"a"},{"role":"assistant","text":"b"}]}"#,
      through: loader)
    #expect(history == [LanguageModelTurn(role: .user, text: "a"), LanguageModelTurn(role: .assistant, text: "b")])
    // Without `messages` the question is as it always was.
    _ = try await send(#"{"type":"llm","prompt":"now"}"#, through: loader)
    #expect(history == [])
  }

  @Test func wrongEntriesOfMessagesAreSkipped() {
    let list: [Any] = [
      ["role": "system", "text": "x"], ["role": "user"], "text", ["role": "user", "text": 5],
      ["role": "user", "text": "kept"],
    ]
    #expect(PluginRegistry.turns(list) == [LanguageModelTurn(role: .user, text: "kept")])
    #expect(PluginRegistry.turns(nil).isEmpty && PluginRegistry.turns("nope").isEmpty)
  }

  @Test func theSystemPromptTheModelAndTheOptionsReachTheLanguageModel() async throws {
    let (registry, loader) = try started()
    var asked: (LanguageModelOptions, String?)?
    registry.askLanguageModel = { _, _, options, name, _ in
      asked = (options, name)
      return "ok"
    }
    _ = try await send(
      #"{"type":"llm","prompt":"p","system":"Be brief.","model":"mlx/pe","options":{"temperature":1,"thinking":true}}"#,
      through: loader)
    #expect(asked?.0 == LanguageModelOptions(system: "Be brief.", temperature: 1, thinking: true))
    #expect(asked?.1 == "mlx/pe")
    // Without the new keys the question is asked as it always was.
    _ = try await send(#"{"type":"llm","prompt":"p"}"#, through: loader)
    #expect(asked?.0 == LanguageModelOptions())
    #expect(asked?.1 == nil)
  }

  @Test func theReasonIsToldInPlainWords() async throws {
    let (registry, loader) = try started()
    registry.askLanguageModel = { _, _, _, _, _ in throw LanguageModelError.noModelSelected }
    let reply = try await send(#"{"type":"llm","prompt":"p"}"#, through: loader)
    #expect(reply["text"] as? String == "No language model is chosen.")
  }

  @Test func aModelThatIsNotThereIsAnError() async throws {
    let (registry, loader) = try started()
    registry.askLanguageModel = { _, _, _, name, _ in throw LanguageModelError.modelNotFound(name ?? "") }
    let reply = try await send(#"{"type":"llm","prompt":"p","model":"nowhere"}"#, through: loader)
    #expect(reply["type"] as? String == "error")
    #expect((reply["text"] as? String)?.contains("nowhere") == true)
  }

  @Test func aQuestionThatCannotBeAnsweredGetsAnError() async throws {
    let (registry, loader) = try started()
    #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
    registry.askLanguageModel = { _, _, _, _, _ in throw LanguageModelError.noModelSelected }
    #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
    #expect(try await send(#"{"type":"llm"}"#, through: loader)["type"] as? String == "error")
    registry.setActive("a", false)
    registry.askLanguageModel = { _, _, _, _, _ in "never" }
    #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
  }
}
