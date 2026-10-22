import Testing

@testable import PromptMasterF3

@MainActor
struct ManifestTests {
  @Test func manifestIsForTheFamiliesOnly() {
    let plugin = F3Plugin()
    #expect(plugin.manifest.families == F3Plugin.families)
    #expect(F3Plugin.families == ["flux3_5b"])
    #expect(plugin.manifest.id == "com.exiztenz.dthub.promptmasterf3")
    // The same toolbar icon as Prompt Master: plug-ins that do the same for different models never show together.
    #expect(plugin.manifest.symbol == "wand.and.stars")
  }
}
