import HubKit
import Testing

@testable import HubCore

/// The catalog carries the user's LoRA trigger words and weights; the server's own stays apart.
@MainActor
struct ConnectionMonitorLoRATests {
  let loraCatalog = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")],
    loras: [CatalogLoRA(file: "fox_lora_f16.ckpt", name: "Fox", family: "flux2_9b", trigger: "foxstyle", defaultWeight: 0.7)],
    fileCount: 2)

  @Test func theCatalogCarriesTheUsersValuesAndTheServerOneStaysApart() async {
    let monitor = ConnectionMonitor()
    var overrides = LoRAOverrides()
    overrides.entries["fox_lora_f16.ckpt"] = LoRAOverride(trigger: "mine", weight: 0.4)
    monitor.loraOverrides = overrides
    await monitor.replaceBackend(FakeBackend(.success(loraCatalog)))
    #expect(monitor.catalog.loras.first?.trigger == "mine" && monitor.catalog.loras.first?.defaultWeight == 0.4)
    #expect(monitor.serverCatalog == loraCatalog)
    #expect(monitor.serverCatalog.loras.first?.trigger == "foxstyle")
  }

  @Test func changingTheValuesUpdatesTheCatalogAtOnceAndSavesThem() async {
    let monitor = ConnectionMonitor()
    var saved: [LoRAOverrides] = []
    monitor.saveLoRAOverrides = { saved.append($0) }
    await monitor.replaceBackend(FakeBackend(.success(loraCatalog)))
    #expect(monitor.catalog.loras.first?.trigger == "foxstyle" && monitor.catalog.loras.first?.defaultWeight == 1)
    monitor.loraOverrides.setTrigger("mine", for: loraCatalog.loras[0])
    #expect(monitor.catalog.loras.first?.trigger == "mine")
    #expect(saved.count == 1 && saved[0].entries["fox_lora_f16.ckpt"]?.trigger == "mine")
  }

  @Test func theValuesSurviveANewCheckOfTheServer() async {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(FakeBackend(.success(loraCatalog)))
    monitor.loraOverrides.setWeight(0.3, for: loraCatalog.loras[0])
    await monitor.refresh()
    #expect(monitor.catalog.loras.first?.defaultWeight == 0.3)
  }

  @Test func anOfflineServerHasNoLoRAsWhateverTheUserSaved() async {
    let monitor = ConnectionMonitor()
    monitor.loraOverrides.setWeight(0.3, for: loraCatalog.loras[0])
    #expect(monitor.catalog == .empty)
    await monitor.refresh()
    #expect(monitor.catalog.loras.isEmpty)
  }
}
