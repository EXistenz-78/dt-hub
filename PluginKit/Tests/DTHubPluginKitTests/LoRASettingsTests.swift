import Foundation
import Testing

@testable import DTHubPluginKit

struct LoRASettingsTests {
  func context(_ extra: String) throws -> DTHubContext {
    try JSONDecoder().decode(DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/tmp/x"\#(extra)}"#.utf8))
  }

  @Test func readsTheNewCatalogFields() throws {
    let lora = try context(
      #","loraCatalog":[{"file":"a.ckpt","category":"turbo","steps":8,"guidance":1.5,"shift":3}]"#
    ).loraCatalog?.first
    #expect(lora?.category == "turbo" && lora?.steps == 8 && lora?.guidance == 1.5 && lora?.shift == 3)
  }

  @Test func theNewFieldsDefaultToNil() throws {
    let lora = try context(#","loraCatalog":[{"file":"a.ckpt"}]"#).loraCatalog?.first
    #expect(lora?.category == nil && lora?.steps == nil && lora?.guidance == nil && lora?.shift == nil)
  }

  @Test func wrongTypesAreIgnoredAndTheLoRAStays() throws {
    let catalog = try context(
      #","loraCatalog":[{"file":"a.ckpt","category":5,"steps":"x","guidance":"y","shift":[1]}]"#
    ).loraCatalog
    #expect(catalog?.count == 1)
    #expect(catalog?.first?.category == nil && catalog?.first?.steps == nil)
    #expect(catalog?.first?.guidance == nil && catalog?.first?.shift == nil)
  }

  @Test func loraSettingsFlagIsOptional() throws {
    #expect(try context("").loraSettings == nil)
    #expect(try context(#","loraSettings":true"#).loraSettings == true)
    #expect(try context(#","loraSettings":false"#).loraSettings == false)
    let bad = try context(#","loraSettings":"yes""#)
    #expect(bad.loraSettings == nil && bad.tempFolder == "/tmp/x")
  }

  @Test func bodyOmitsKeep() {
    let body = DTHubLoRASettings.body(file: "a.ckpt", settings: DTHubLoRASettings())
    #expect(body.count == 2)
    #expect(body["type"] as? String == "loraSettings" && body["file"] as? String == "a.ckpt")
  }

  @Test func bodyClearsAndSets() {
    let settings = DTHubLoRASettings(
      trigger: .set(""), category: .clear, steps: .set(8), guidance: .set(1.5), shift: .clear)
    let body = DTHubLoRASettings.body(file: "a.ckpt", settings: settings)
    #expect(body["trigger"] as? String == "")
    #expect(body["category"] is NSNull)
    #expect(body["steps"] as? Int == 8)
    #expect(body["guidance"] as? Double == 1.5)
    #expect(body["shift"] is NSNull)
  }

  @Test func bodySerializesAsJSON() throws {
    let body = DTHubLoRASettings.body(file: "a", settings: DTHubLoRASettings(category: .clear, steps: .set(4)))
    let data = try JSONSerialization.data(withJSONObject: body)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["category"] is NSNull && object["steps"] as? Int == 4 && object["trigger"] == nil)
  }
}
