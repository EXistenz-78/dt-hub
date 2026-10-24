import Testing

@testable import Flux3Editing

@MainActor
struct ManifestTests {
  @Test func manifestIsForTheFamiliesOnly() {
    let plugin = Flux3EditingPlugin()
    #expect(plugin.manifest.families == Flux3EditingPlugin.families)
    #expect(Flux3EditingPlugin.families == ["flux3_5b"])
    #expect(plugin.manifest.id == "com.exiztenz.dthub.flux3editing")
    #expect(plugin.manifest.name == "Flux3 Editing")
    #expect(plugin.manifest.version == "1.1")
    // The same icon as Qwen 2.1 Inpainting: plug-ins that do the same for different models never show together.
    #expect(plugin.manifest.symbol == "scribble.variable")
  }
}
