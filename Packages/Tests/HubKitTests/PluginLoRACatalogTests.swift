import Foundation
import Testing

@testable import HubKit

struct PluginLoRACatalogTests {
  func json(_ context: PluginContext) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
  }

  func context(_ catalog: [PluginCatalogLoRA]?) -> PluginContext {
    PluginContext(model: nil, family: nil, parameters: GenerationParameters(), tempFolder: "/tmp/x", loraCatalog: catalog)
  }

  @Test func theContextCarriesTheLoRACatalog() throws {
    let catalog = [
      PluginCatalogLoRA(CatalogLoRA(file: "a.ckpt", name: "A", family: "flux2_9b", trigger: "aa", defaultWeight: 0.8)),
      PluginCatalogLoRA(CatalogLoRA(file: "b.ckpt", name: "B", family: nil)),
    ]
    let list = try #require(try json(context(catalog))["loraCatalog"] as? [[String: Any]])
    #expect(list.count == 2)
    #expect(list[0]["file"] as? String == "a.ckpt" && list[0]["name"] as? String == "A")
    #expect(list[0]["family"] as? String == "flux2_9b" && list[0]["trigger"] as? String == "aa")
    #expect(list[0]["weight"] as? Double == 0.8)
    #expect(list[1]["family"] == nil)
    #expect(list[1]["trigger"] as? String == "" && list[1]["weight"] as? Double == 1)
  }

  @Test func withoutACatalogTheKeyIsLeftOutAndAnEmptyOneIsSent() throws {
    #expect(try json(context(nil))["loraCatalog"] == nil)
    #expect((try json(context([]))["loraCatalog"] as? [Any])?.isEmpty == true)
  }
}
