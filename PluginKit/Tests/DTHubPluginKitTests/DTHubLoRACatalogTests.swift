import Foundation
import Testing

@testable import DTHubPluginKit

struct DTHubLoRACatalogTests {
  func context(_ catalog: String?) throws -> DTHubContext {
    let extra = catalog.map { #","loraCatalog":\#($0)"# } ?? ""
    return try JSONDecoder().decode(DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/tmp/x"\#(extra)}"#.utf8))
  }

  @Test func readsTheLoRACatalog() throws {
    let catalog = try context(
      #"[{"file":"a.ckpt","name":"A","family":"flux2_9b","trigger":"aa","weight":0.8},{"file":"b.ckpt","name":"B","trigger":"","weight":1}]"#
    ).loraCatalog
    #expect(
      catalog == [
        DTHubCatalogLoRA(file: "a.ckpt", name: "A", family: "flux2_9b", trigger: "aa", weight: 0.8),
        DTHubCatalogLoRA(file: "b.ckpt", name: "B", family: nil, trigger: "", weight: 1),
      ])
  }

  @Test func aBadEntryIsSkipped() throws {
    let catalog = try context(#"[{"file":"a.ckpt"}, 7, {"name":"x"}, {"file":"c.ckpt","weight":"x"}, {"file":""}]"#).loraCatalog
    #expect(
      catalog == [
        DTHubCatalogLoRA(file: "a.ckpt", name: "a.ckpt", family: nil, trigger: "", weight: 1),
        DTHubCatalogLoRA(file: "c.ckpt", name: "c.ckpt", family: nil, trigger: "", weight: 1),
      ])
  }

  @Test func aCatalogThatIsNotAListCostsNothing() throws {
    let read = try context("5")
    #expect(read.loraCatalog == nil && read.tempFolder == "/tmp/x")
  }

  @Test func anOldAppSendsNoCatalogAndANewOneMaySendAnEmptyOne() throws {
    #expect(try context(nil).loraCatalog == nil)
    #expect(try context("[]").loraCatalog == [])
  }
}
