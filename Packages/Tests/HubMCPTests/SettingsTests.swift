import Foundation
import Testing

@testable import HubMCP

struct SettingsTests {
  @Test func defaultsAreOffAndReadOnly() {
    let s = RemoteControlSettings()
    #expect(s.enabled == false)
    #expect(s.mode == .readOnly)
    #expect(s.confirmThreshold == 20)
    #expect(s.imageBudget == 200)
    #expect(s.confirmTimeoutSeconds == 60)
    #expect(s.port == 8765)
  }

  @Test func missingFieldsTakeDefaults() throws {
    let s = try JSONDecoder().decode(RemoteControlSettings.self, from: Data(#"{"enabled":true}"#.utf8))
    #expect(s.enabled == true)
    #expect(s.mode == .readOnly)
    #expect(s.imageBudget == 200)
  }

  @Test func clampedKeepsRanges() {
    var s = RemoteControlSettings()
    s.confirmThreshold = 0
    s.confirmTimeoutSeconds = 9999
    s.imageBudget = -3
    let c = s.clamped()
    #expect(c.confirmThreshold == 1)
    #expect(c.confirmTimeoutSeconds == 600)
    #expect(c.imageBudget == 1)
  }

  @Test func accessModeOrdering() {
    #expect(AccessMode.readOnly < .editFields)
    #expect(AccessMode.editFields < .full)
  }

  @Test func storeRoundTrips() {
    let suite = "hubmcp.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RemoteControlSettingsStore(defaults: defaults)
    var s = RemoteControlSettings()
    s.enabled = true
    s.mode = .full
    s.port = 9000
    store.save(s)
    #expect(store.load() == s)
  }

  @Test func agentValueRoundTripsThroughJSON() throws {
    let values: [AgentValue] = [.string("a"), .int(3), .double(1.5), .bool(true)]
    let data = try JSONEncoder().encode(values)
    #expect(try JSONDecoder().decode([AgentValue].self, from: data) == values)
  }
}
