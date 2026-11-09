import Testing

@testable import HubMCP

@MainActor
struct CallLogTests {
  @Test func callLogKeepsLast200Entries() {
    let log = CallLog()
    for index in 0..<250 { log.record(tool: "t\(index)", isError: false, detail: "") }
    #expect(log.entries.count == 200)
    #expect(log.entries.first?.tool == "t50")
    #expect(log.entries.last?.tool == "t249")
  }

  @Test func registryRecordsEveryCallIncludingFailures() async {
    let h = Harness()
    _ = await h.registry.call("get_app_state", arguments: [:])
    _ = await h.registry.call("nope", arguments: [:])
    #expect(h.registry.callLog.entries.map(\.tool) == ["get_app_state", "nope"])
    #expect(h.registry.callLog.entries.map(\.isError) == [false, true])
  }

  @Test func clearEmptiesTheLog() {
    let log = CallLog()
    log.record(tool: "a", isError: false, detail: "")
    log.clear()
    #expect(log.entries.isEmpty)
  }
}
