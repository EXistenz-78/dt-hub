import Foundation
import Testing

@testable import HubKit

struct PluginContractTests {
  @Test func theManifestNeedsOnlyTheIdTheNameAndTheContract() throws {
    let manifest = try JSONDecoder().decode(
      PluginManifest.self, from: Data(#"{"id":"com.x.p","name":"P","contract":1}"#.utf8))
    #expect(manifest == PluginManifest(id: "com.x.p", name: "P", version: "0", contract: 1))
    #expect(manifest.symbol == "puzzlepiece.extension" && manifest.families == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PluginManifest.self, from: Data(#"{"name":"P","contract":1}"#.utf8))
    }
  }

  @Test func aPluginWorksWithTheFamiliesItNamesAndWithAnUnknownOne() {
    var manifest = PluginManifest(id: "a", name: "A")
    #expect(manifest.supports(family: "flux2_9b") && manifest.supports(family: nil))
    manifest.families = ["qwen21"]
    #expect(manifest.supports(family: "qwen21"))
    #expect(!manifest.supports(family: "flux2_9b"))
    #expect(manifest.supports(family: nil), "an unknown family: everything applies")
    manifest.families = []
    #expect(manifest.supports(family: "flux2_9b"), "an empty list means all")
  }

  @Test func versionsAreComparedNumberByNumber() {
    #expect(PluginVersion("1.10") > PluginVersion("1.9"))
    #expect(PluginVersion("2") > PluginVersion("1.9.9"))
    #expect(PluginVersion("1.0") == PluginVersion("1.0.0"))
    #expect(!(PluginVersion("1.2") > PluginVersion("1.2")))
    #expect(PluginVersion("0") < PluginVersion("0.0.1"))
  }

  @Test func theMessageTypeIsReadFromTheJSON() {
    #expect(PluginMessageType.of(Data(#"{"type":"notice","text":"x"}"#.utf8)) == "notice")
    #expect(PluginMessageType.of(Data("nonsense".utf8)) == nil)
    #expect(PluginMessageType.of(PluginMessageType.bare("ok")) == "ok")
  }

  @Test func aNoticeAsksForTheTextOnly() throws {
    let notice = try JSONDecoder().decode(PluginNotice.self, from: Data(#"{"type":"notice","text":"Ready"}"#.utf8))
    #expect(notice.text == "Ready" && notice.isError == false)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PluginNotice.self, from: Data(#"{"type":"notice"}"#.utf8))
    }
  }

  @Test func theContextCarriesTheModelTheParametersAndTheFolder() throws {
    let context = PluginContext(
      model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(width: 512), tempFolder: "/tmp/x")
    let data = try JSONEncoder().encode(context)
    #expect(PluginMessageType.of(data) == PluginMessageType.context)
    let back = try JSONDecoder().decode(PluginContext.self, from: data)
    #expect(back == context)
  }
}
