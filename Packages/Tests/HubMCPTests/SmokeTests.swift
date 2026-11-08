import Testing

@testable import HubMCP

struct SmokeTests {
  @Test func moduleNameIsHubMCP() {
    #expect(HubMCP.moduleName == "HubMCP")
  }
}
