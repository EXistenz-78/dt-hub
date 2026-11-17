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
    #expect(LATools.declarations.map(\.name) == [
      "list_loras", "get_lora", "set_notes", "set_weight_limits", "set_category", "set_turbo_settings", "set_trigger",
    ])
    let json = try JSONEncoder().encode(LATools.declarations)
    #expect(try JSONSerialization.jsonObject(with: json) is [[String: Any]])
    #expect(LATools.declarations.filter { $0.level != .read }.map(\.name) == [
      "set_notes", "set_weight_limits", "set_category", "set_turbo_settings", "set_trigger",
    ])
    #expect(LATools.declarations.prefix(2).allSatisfy { $0.level == .read })
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
    #expect((rows?.first?["summary"] as? String)?.count ?? 0 < 820)
    let detail = object(await call("get_lora", ["file": "a.ckpt"]).text)
    #expect(detail["summary"] as? String == long)
  }

  @Test func theListGivesFamilyWeightsSummaryAndLink() async {
    start()
    store.update("a.ckpt") { $0.link = "https://civitai.com/models/1"; $0.notes = "Detail slider. Weight 0.6-1."; $0.rawNotes = true }
    let rows = object(await call("list_loras").text)["loras"] as? [[String: Any]]
    let a = rows?.first { $0["file"] as? String == "a.ckpt" }
    #expect(a?["family"] as? String == "b" && a?["weight"] as? Double == 0.8 && a?["trigger"] as? String == "aa")
    #expect(a?["minWeight"] is NSNull && a?["maxWeight"] is NSNull)
    #expect(a?["summary"] as? String == "Detail slider. Weight 0.6-1." && a?["summaryIsRaw"] as? Bool == true)
    #expect(a?["link"] as? String == "https://civitai.com/models/1")
    #expect(rows?.first { $0["file"] as? String == "p.ckpt" }?["link"] is NSNull)
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
    #expect(await call("advise").type == "unsupported")
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

  // MARK: category, turbo settings and trigger

  /// A context with the app able to take settings, and a fake `saveSettings` that records what it gets.
  func connect(_ sent: LAStateTests.Sent, catalog: String = LAStateTests.kinds) {
    state.active = true
    state.apply(context: helper.settingsContext(catalog: catalog))
    state.saveSettings = { file, settings in
      sent.settings.append((file, settings))
      return sent.answer
    }
  }

  static let rich = """
    [{"file":"a.ckpt","name":"Alpha","family":"b","trigger":"aa","weight":1,"category":"turbo","steps":8,"guidance":1.5,"shift":3},
     {"file":"p.ckpt","name":"Piu luce","family":"b","trigger":"","weight":1,"category":"style","steps":20,"guidance":4},
     {"file":"u.ckpt","name":"Unknown","family":"b","trigger":"","weight":1}]
    """

  @Test func rowsCarryCategoryTurboValuesAndTheTriggerProposal() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    store.update("u.ckpt") { $0.triggerProposal = "uu" }
    let rows = object(await call("list_loras").text)["loras"] as? [[String: Any]]
    let a = rows?.first { $0["file"] as? String == "a.ckpt" }
    #expect(a?["category"] as? String == "turbo" && a?["steps"] as? Int == 8 && a?["guidance"] as? Double == 1.5 && a?["shift"] as? Double == 3)
    #expect(a?["triggerProposal"] is NSNull)
    let p = rows?.first { $0["file"] as? String == "p.ckpt" }
    #expect(p?["category"] as? String == "style" && p?["steps"] is NSNull && p?["guidance"] is NSNull && p?["shift"] is NSNull)
    let u = object(await call("get_lora", ["file": "u.ckpt"]).text)
    #expect(u["category"] is NSNull && u["steps"] is NSNull && u["shift"] is NSNull && u["triggerProposal"] as? String == "uu")
  }

  @Test func theCategoryParameterNarrowsTheList() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    func files(_ arguments: [String: Any]) async -> [String?] {
      (object(await call("list_loras", arguments).text)["loras"] as? [[String: Any]])?.map { $0["file"] as? String } ?? []
    }
    #expect(await files(["category": "turbo"]) == ["a.ckpt"])
    #expect(await files(["category": "style"]) == ["p.ckpt"])
    #expect(await files(["category": "none"]) == ["u.ckpt"])
    #expect(await files(["category": "style", "query": "alpha"]).isEmpty)
    #expect(await call("list_loras", ["category": "bogus"]).isError)
  }

  @Test func setCategoryWritesThroughTheApp() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    let answer = await call("set_category", ["file": "u.ckpt", "category": "slider"])
    #expect(!answer.isError)
    #expect(object(answer.text)["file"] as? String == "u.ckpt" && object(answer.text)["category"] as? String == "slider")
    #expect(sent.settings.count == 1 && sent.settings[0].0 == "u.ckpt")
    #expect(store.entry(for: "u.ckpt").categoryManual)
    #expect(state.catalog.first { $0.file == "u.ckpt" }?.category == "slider")
    let cleared = await call("set_category", ["file": "p.ckpt", "category": "none"])
    #expect(!cleared.isError && object(cleared.text)["category"] is NSNull)
    #expect(state.catalog.first { $0.file == "p.ckpt" }?.category == nil)
    let before = sent.settings.count
    #expect(await call("set_category", ["file": "u.ckpt", "category": "weird"]).isError)
    #expect(await call("set_category", ["file": "u.ckpt"]).isError)
    #expect(await call("set_category", ["file": "ghost.ckpt", "category": "style"]).isError)
    #expect(sent.settings.count == before)
  }

  @Test func setTurboSettingsWritesAndChecksTheRanges() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    let answer = await call("set_turbo_settings", ["file": "a.ckpt", "steps": 4, "guidance": 1, "shift": 5])
    #expect(!answer.isError)
    let result = object(answer.text)
    #expect(result["steps"] as? Int == 4 && result["guidance"] as? Double == 1 && result["shift"] as? Double == 5)
    #expect(sent.settings.count == 1 && store.entry(for: "a.ckpt").paramsManual)
    #expect(state.catalog.first { $0.file == "a.ckpt" }?.steps == 4)
    let before = sent.settings.count
    for bad: [String: Any] in [
      ["steps": 0], ["steps": 201], ["steps": 2.5], ["guidance": -1], ["guidance": 51], ["shift": 51], [:],
    ] {
      var arguments = bad
      arguments["file"] = "a.ckpt"
      #expect(await call("set_turbo_settings", arguments).isError, Comment(rawValue: "\(bad)"))
    }
    let range = await call("set_turbo_settings", ["file": "a.ckpt", "steps": 0])
    #expect(range.text.contains("1") && range.text.contains("200"))
    // Not a Turbo LoRA: the category comes first.
    let notTurbo = await call("set_turbo_settings", ["file": "p.ckpt", "steps": 8])
    #expect(notTurbo.isError && notTurbo.text.contains("set_category"))
    #expect(await call("set_turbo_settings", ["file": "u.ckpt", "steps": 8]).isError)
    #expect(sent.settings.count == before)
  }

  @Test func omittedTurboValuesStayAsTheyAre() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    #expect(!(await call("set_turbo_settings", ["file": "a.ckpt", "steps": 4])).isError)
    var a = state.catalog.first { $0.file == "a.ckpt" }
    #expect(a?.steps == 4 && a?.guidance == 1.5 && a?.shift == 3)
    let answer = await call("set_turbo_settings", ["file": "a.ckpt", "guidance": 2, "shift": 6])
    a = state.catalog.first { $0.file == "a.ckpt" }
    #expect(a?.steps == 4 && a?.guidance == 2 && a?.shift == 6)
    #expect(object(answer.text)["steps"] as? Int == 4)
  }

  @Test func theTriggerIsBounded() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    let long = await call("set_trigger", ["file": "u.ckpt", "trigger": String(repeating: "x", count: 201)])
    #expect(long.isError && long.text.contains("200") && sent.settings.isEmpty)
    #expect(!(await call("set_trigger", ["file": "u.ckpt", "trigger": String(repeating: "x", count: 200)])).isError)
  }

  @Test func setTriggerWritesAndClearsTheProposal() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    store.update("u.ckpt") { $0.triggerProposal = "uu" }
    let answer = await call("set_trigger", ["file": "u.ckpt", "trigger": "  my trigger "])
    #expect(!answer.isError && object(answer.text)["trigger"] as? String == "my trigger")
    #expect(sent.settings.count == 1 && store.entry(for: "u.ckpt").triggerProposal == nil)
    #expect(state.catalog.first { $0.file == "u.ckpt" }?.trigger == "my trigger")
    #expect(!(await call("set_trigger", ["file": "a.ckpt", "trigger": ""])).isError)
    #expect(state.catalog.first { $0.file == "a.ckpt" }?.trigger == "")
    #expect(await call("set_trigger", ["file": "a.ckpt"]).isError)
  }

  @Test func aStaleUIFailureDoesNotMakeANoOpToolCallFail() async {
    let sent = LAStateTests.Sent()
    connect(sent, catalog: Self.rich)
    #expect(!(await call("set_trigger", ["file": "u.ckpt", "trigger": "x"])).isError)
    sent.answer = ["type": "error"]
    await state.setCategory(.style, for: "u.ckpt")
    #expect(state.settingsMessage != nil)
    sent.answer = ["type": "ok"]
    let count = sent.settings.count
    #expect(!(await call("set_trigger", ["file": "u.ckpt", "trigger": "x"])).isError)
    #expect(sent.settings.count == count && state.settingsMessage == nil)
  }

  @Test func theNewToolsFailWithAnOldAppOrAFailedSave() async {
    start(loras: "[]")
    let old = await call("set_category", ["file": "a.ckpt", "category": "style"])
    #expect(old.isError && old.text == "This DT Hub is too old to change these settings.")
    #expect(await call("set_turbo_settings", ["file": "a.ckpt", "steps": 4]).text == old.text)
    #expect(await call("set_trigger", ["file": "a.ckpt", "trigger": "x"]).text == old.text)

    let sent = LAStateTests.Sent()
    sent.answer = ["type": "error"]
    connect(sent, catalog: Self.rich)
    for (tool, arguments) in [
      ("set_category", ["file": "u.ckpt", "category": "style"]), ("set_turbo_settings", ["file": "a.ckpt", "steps": 4]),
      ("set_trigger", ["file": "u.ckpt", "trigger": "x"]),
    ] as [(String, [String: Any])] {
      let failed = await call(tool, arguments)
      #expect(failed.isError && failed.text == state.settingsMessage, Comment(rawValue: tool))
    }
    #expect(state.catalog.first { $0.file == "u.ckpt" }?.category == nil && !store.entry(for: "u.ckpt").categoryManual)
  }
}
