import Foundation
import Testing

@testable import HubMCP

@MainActor
struct MemoryStateTests {
  @Test func getAppStateCarriesTheMemoryReading() async {
    let h = Harness()
    h.host.stateValue.memory = AgentMemoryReading(
      totalGB: 64, availableGB: 18.5, pressure: "warning", swapUsedGB: 1.2, appGB: 2.1, serverGB: 21)
    let result = await h.registry.call("get_app_state", arguments: [:])
    guard case .text(let text)? = result.outputs.first else { Issue.record("no text"); return }
    #expect(text.contains("\"memory\""))
    #expect(text.contains("\"availableGB\" : 18.5") || text.contains("\"availableGB\":18.5"))
    #expect(text.contains("\"pressure\" : \"warning\"") || text.contains("\"pressure\":\"warning\""))
  }

  @Test func theMemoryReadingIsAbsentWhenNoneWasTaken() async {
    let h = Harness()
    let result = await h.registry.call("get_app_state", arguments: [:])
    guard case .text(let text)? = result.outputs.first else { Issue.record("no text"); return }
    #expect(!text.contains("\"memory\""))
  }

  @Test func theInstructionsMentionMemoryAndStayShort() {
    #expect(AgentInstructions.short.contains("memory"))
    #expect(AgentInstructions.short.count < 1600)
  }
}
