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
    #expect(LATools.declarations.map(\.name) == ["list_loras", "get_lora", "set_notes", "set_weight_limits"])
    let json = try JSONEncoder().encode(LATools.declarations)
    #expect(try JSONSerialization.jsonObject(with: json) is [[String: Any]])
    #expect(LATools.declarations.filter { $0.level != .read }.map(\.name) == ["set_notes", "set_weight_limits"])
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
}
