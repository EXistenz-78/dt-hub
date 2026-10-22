import Testing

@testable import Flux3Editing

@MainActor
struct ManifestTests {
  @Test func manifestIsForTheFamiliesOnly() {
    let plugin = Flux3EditingPlugin()
    #expect(plugin.manifest.families == Flux3EditingPlugin.families)
    #expect(Flux3EditingPlugin.families == ["flux2_9b", "flux2_4b"])
    #expect(plugin.manifest.id == "com.exiztenz.dthub.flux3editing")
    #expect(plugin.manifest.name == "Flux3 Editing")
    #expect(plugin.manifest.version == "1.0")
    #expect(!plugin.manifest.symbol.isEmpty)
  }
}
