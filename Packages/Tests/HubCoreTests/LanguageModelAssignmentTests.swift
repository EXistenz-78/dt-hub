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

  @Test func useCoversTheRightSituations() {
    // (use, Enhance with an empty Control, Enhance with pictures, Generate)
    let table: [(LanguageModelUse, Bool, Bool, Bool)] = [
      (.enhance, true, true, false), (.describe, false, false, true), (.both, true, true, true),
      (.pluginsOnly, false, false, false), (.i2i, false, true, true), (.t2i, true, false, false),
    ]
    for (use, empty, withImages, generate) in table {
      #expect(use.covers(.enhance, controlHasImages: false) == empty, "\(use) enhance empty")
      #expect(use.covers(.enhance, controlHasImages: true) == withImages, "\(use) enhance images")
      #expect(use.covers(.describe, controlHasImages: true) == generate, "\(use) generate")
    }
  }

  @Test func i2iAndT2iAreSavedByName() throws {
    for use in [LanguageModelUse.i2i, .t2i] {
      let data = try JSONEncoder().encode(LanguageModelAssignment(family: .allOthers, use: use))
      #expect(String(data: data, encoding: .utf8)?.contains("\"\(use.rawValue)\"") == true)
      #expect(try JSONDecoder().decode(LanguageModelAssignment.self, from: data).use == use)
    }
    #expect(LanguageModelUse.i2i.rawValue == "i2i" && LanguageModelUse.t2i.rawValue == "t2i")
    for old in ["enhance", "describe", "both", "pluginsOnly"] {
      #expect(LanguageModelUse(rawValue: old) != nil)
    }
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
    #expect(fields(.family("x"), .i2i) == ["x", "i2i"])
    #expect(fields(.family("x"), .t2i) == ["x", "t2i"])
  }
}
