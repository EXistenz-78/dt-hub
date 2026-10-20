import Testing

@testable import PromptMasterF3

@MainActor
struct ManifestTests {
  @Test func manifestIsForTheFamiliesOnly() {
    let plugin = F3Plugin()
    #expect(plugin.manifest.families == F3Plugin.families)
    #expect(plugin.manifest.id == "com.exiztenz.dthub.promptmasterf3")
  }
}
