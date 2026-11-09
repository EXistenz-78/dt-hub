import DTHubPluginKit
import Foundation
import Testing

@testable import LoRAAdvisor

@MainActor
struct LAToolsTests {
  let store = LAStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("la-tools-\(UUID().uuidString)", isDirectory: true))
  let state: LAState
  let helper = LAStateTests()

  init() {
    let fetcher = FakeFetcher()
    let jobs = LAJobs(store: store, fetcher: fetcher, summarise: { _, _ in nil }, pause: .zero, italian: false)
    state = LAState(store: store, jobs: jobs, fetcher: fetcher, italian: false)
  }

  func start(models: String = #"[{"name":"llm","path":"/x","supportsImages":false}]"#, loras: String = "[]") {
    state.active = true
    state.apply(context: helper.context(loras: loras, models: models))
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> (text: String, isError: Bool, type: String?) {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let data = try! JSONSerialization.data(withJSONObject: body)
    let answer = await LATools.handle(DTHubToolCall(data)!, state: state)
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return (object["text"] as? String ?? "", object["isError"] as? Bool ?? false, object["type"] as? String)
  }

  func object(_ text: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in LATools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    #expect(LATools.declarations.map(\.name) == ["list_loras", "get_lora", "advise", "apply_advice", "set_notes", "set_weight_limits"])
    let json = try JSONEncoder().encode(LATools.declarations)
    #expect(try JSONSerialization.jsonObject(with: json) is [[String: Any]])
    #expect(LATools.declarations.filter { $0.level != .read }.map(\.name) == ["apply_advice", "set_notes", "set_weight_limits"])
  }

  @Test func listingStartsWithTheCurrentFamilyAndCanShowAll() async {
    start()
    let current = object(await call("list_loras").text)
    #expect((current["loras"] as? [[String: Any]])?.map { $0["file"] as? String } == ["a.ckpt", "p.ckpt", "u.ckpt"])
    #expect(current["currentFamily"] as? String == "b")
    let all = object(await call("list_loras", ["scope": "all"]).text)
    #expect(all["total"] as? Int == 4)
    let found = object(await call("list_loras", ["scope": "all", "query": "ZETA"]).text)
    #expect((found["loras"] as? [[String: Any]])?.count == 1)
    let limited = object(await call("list_loras", ["limit": 1]).text)
    #expect(limited["shown"] as? Int == 1 && limited["total"] as? Int == 3)
  }

  @Test func listingSaysIfALoRAIsOnTheTab() async {
    start(loras: #"[{"file":"a.ckpt","weight":0.8}]"#)
    let rows = object(await call("list_loras").text)["loras"] as? [[String: Any]]
    #expect(rows?.first { $0["file"] as? String == "a.ckpt" }?["onTab"] as? Bool == true)
    #expect(rows?.first { $0["file"] as? String == "p.ckpt" }?["onTab"] as? Bool == false)
  }

  @Test func notesAreShortInTheListAndWholeInTheDetail() async {
    start()
    let long = String(repeating: "word ", count: 200)
    store.setNotesByUser(long, for: "a.ckpt")
    let rows = object(await call("list_loras").text)["loras"] as? [[String: Any]]
    #expect((rows?.first?["notes"] as? String)?.count ?? 0 < 260)
    let detail = object(await call("get_lora", ["file": "a.ckpt"]).text)
    #expect(detail["notes"] as? String == long)
  }

  @Test func anUnknownLoRAIsAnErrorWithAHint() async {
    start()
    let answer = await call("get_lora", ["file": "nope.ckpt"])
    #expect(answer.isError && answer.text.contains("list_loras"))
  }

  @Test func nothingWorksBeforeTheAppHasTalkedOrWhenNotActive() async {
    let answer = await call("list_loras")
    #expect(answer.isError)
  }

  @Test func anUnknownToolIsUnsupported() async {
    start()
    #expect(await call("explode").type == "unsupported")
  }

  // MARK: advise and apply

  @Test func adviceFollowsTheGoalAndLeavesTheTabsFieldAlone() async {
    start()
    var asked: [String] = []
    state.askModel = { _, prompt in
      asked.append(prompt)
      return .text(#"[{"n":2,"weight":0.7,"why":"more light"}]"#)
    }
    let answer = await call("advise", ["goal": "bright portrait"])
    #expect(!answer.isError)
    #expect(asked.first?.contains("bright portrait") == true)
    #expect(state.request == "un prompt" && !state.requestEditedByUser)
    let suggestions = object(answer.text)["suggestions"] as? [[String: Any]]
    #expect(suggestions?.first?["file"] as? String == "p.ckpt" && suggestions?.first?["weight"] as? Double == 0.7)
  }

  @Test func adviceWithoutALanguageModelOrCandidatesExplainsWhy() async {
    start(models: "[]")
    #expect(await call("advise", ["goal": "x"]).text.contains("language model"))
    let none = LAToolsTests()
    none.state.active = true
    none.state.apply(context: none.helper.context(catalog: #"[{"file":"z.ckpt","name":"Zeta","family":"a"}]"#))
    #expect(await none.call("advise", ["goal": "x"]).text.contains("family"))
  }

  @Test func adviceAsksNothingWhenTheModelFails() async {
    start()
    state.askModel = { _, _ in .failure("Out of memory.") }
    let answer = await call("advise", ["goal": "x"])
    #expect(answer.isError && answer.text.contains("Out of memory"))
  }

  @Test func applyingAdvicePutsTheSuggestedLoRAsOnTheTab() async {
    start()
    state.askModel = { _, _ in .text(#"[{"n":1,"weight":0.5},{"n":2,"weight":1.1}]"#) }
    var sent: [[String: Any]] = []
    state.contribute = { body in
      sent.append(body)
      return ["type": "ok"]
    }
    #expect(await call("apply_advice").isError)  // no advice yet
    _ = await call("advise", ["goal": "x"])
    let answer = await call("apply_advice", ["files": "p.ckpt"])
    #expect(!answer.isError)
    let loras = sent.first?["loras"] as? [[String: Any]]
    #expect(loras?.count == 1 && loras?.first?["file"] as? String == "p.ckpt" && loras?.first?["weight"] as? Double == 1.1)
    #expect(await call("apply_advice", ["files": "ghost.ckpt"]).isError)
    #expect(sent.count == 1)
  }

  @Test func aRefusalFromTheAppReachesTheAgent() async {
    start()
    state.askModel = { _, _ in .text(#"[{"n":1}]"#) }
    state.contribute = { _ in ["type": "error", "text": "Pipeline running."] }
    _ = await call("advise", ["goal": "x"])
    let answer = await call("apply_advice")
    #expect(answer.isError && answer.text.contains("Pipeline running"))
  }

  // MARK: notes and limits

  @Test func notesAreWrittenAsTheUsersOwnAndBounded() async {
    start()
    #expect(!(await call("set_notes", ["file": "a.ckpt", "notes": "My notes"])).isError)
    #expect(store.entry(for: "a.ckpt").notes == "My notes" && !store.entry(for: "a.ckpt").rawNotes)
    #expect(await call("set_notes", ["file": "a.ckpt", "notes": String(repeating: "x", count: 4001)]).isError)
    #expect(store.entry(for: "a.ckpt").notes == "My notes")
    #expect(await call("set_notes", ["file": "ghost.ckpt", "notes": "x"]).isError)
  }

  @Test func weightLimitsKeepWhatIsNotGiven() async {
    start()
    var sent: [(String, Double?, Double?, Double?)] = []
    state.saveWeights = { file, low, base, high in
      sent.append((file, low, base, high))
      return ["type": "ok"]
    }
    let answer = await call("set_weight_limits", ["file": "a.ckpt", "max": 1.5])
    #expect(!answer.isError)
    #expect(sent.count == 1 && sent[0].1 == nil && sent[0].2 == 0.8 && sent[0].3 == 1.5)
    #expect(await call("set_weight_limits", ["file": "a.ckpt"]).isError)
    #expect(await call("set_weight_limits", ["file": "a.ckpt", "max": 9]).isError)
    #expect(sent.count == 1)
  }

  @Test func aFailureToSaveTheLimitsIsReported() async {
    start()
    state.saveWeights = { _, _, _, _ in ["type": "error"] }
    #expect(await call("set_weight_limits", ["file": "a.ckpt", "base": 1.2]).isError)
  }
}
