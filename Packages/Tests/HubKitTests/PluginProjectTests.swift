import Foundation
import Testing

@testable import HubKit

struct PluginProjectTests {
  @Test func theMessageHasTheExactKeys() throws {
    let data = try JSONEncoder().encode(PluginProject(name: "Campagna", folder: "/x/.dthub/plugins/a", adoptLegacy: true))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["type", "name", "folder", "adoptLegacy"])
    #expect(object["type"] as? String == "project")
    #expect(object["name"] as? String == "Campagna")
    #expect(object["folder"] as? String == "/x/.dthub/plugins/a")
    #expect(object["adoptLegacy"] as? Bool == true)
  }

  @Test func adoptingTheOldStateIsOffByDefault() {
    #expect(!PluginProject(name: "A", folder: "/f").adoptLegacy)
  }

  @Test func theTypeIsKnown() {
    #expect(PluginMessageType.project == "project")
    let data = try? JSONEncoder().encode(PluginProject(name: "A", folder: "/f"))
    #expect(data.flatMap { PluginMessageType.of($0) } == "project")
  }
}
