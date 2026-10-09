import Foundation
import HubKit
import Testing

@testable import HubCore

struct LanguageModelAssignmentTests {
  @Test func familyEncodesAsOneString() throws {
    for (family, text) in [
      (LanguageModelFamily.none, "\"\""), (.allOthers, "\"*\""), (.family("qwen_image_2.1"), "\"qwen_image_2.1\""),
    ] {
      let data = try JSONEncoder().encode(family)
      #expect(String(data: data, encoding: .utf8) == text)
      #expect(try JSONDecoder().decode(LanguageModelFamily.self, from: data) == family)
    }
    #expect(try JSONDecoder().decode(LanguageModelFamily.self, from: Data("\"whatever\"".utf8)) == .family("whatever"))
  }

  @Test func useCoversTheRightTasks() {
    #expect(LanguageModelUse.enhance.covers(.enhance) && !LanguageModelUse.enhance.covers(.describe))
    #expect(LanguageModelUse.describe.covers(.describe) && !LanguageModelUse.describe.covers(.enhance))
    #expect(LanguageModelUse.both.covers(.enhance) && LanguageModelUse.both.covers(.describe))
    #expect(!LanguageModelUse.pluginsOnly.covers(.enhance) && !LanguageModelUse.pluginsOnly.covers(.describe))
  }

  @Test func oldSettingsDecodeWithNoAssignments() throws {
    let old = Data(#"{"folder":"/x","selectedModel":"/x/m","freeAtRun":true}"#.utf8)
    let settings = try JSONDecoder().decode(LanguageModelSettings.self, from: old)
    #expect(settings.assignments.isEmpty)
    #expect(settings.selectedModel == "/x/m")
  }

  @Test func assignmentsRoundTrip() throws {
    var settings = LanguageModelSettings()
    settings.assignments = [
      "a": LanguageModelAssignment(family: .family("qwen_image_2.1"), use: .enhance),
      "b": LanguageModelAssignment(family: .allOthers, use: .both),
    ]
    let back = try JSONDecoder().decode(LanguageModelSettings.self, from: JSONEncoder().encode(settings))
    #expect(back.assignments == settings.assignments)
  }

  @Test func pluginFieldsMapEveryCombination() {
    func fields(_ f: LanguageModelFamily, _ u: LanguageModelUse) -> [String?] {
      let r = LanguageModelAssignment(family: f, use: u).pluginFields
      return [r.family, r.use]
    }
    #expect(fields(.none, .both) == [nil, "both"])
    #expect(fields(.allOthers, .enhance) == ["*", "enhance"])
    #expect(fields(.family("qwen_image_2.1"), .describe) == ["qwen_image_2.1", "describe"])
    #expect(fields(.family("x"), .pluginsOnly) == ["x", "plugins"])
  }
}
