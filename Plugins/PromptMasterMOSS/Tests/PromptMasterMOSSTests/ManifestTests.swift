import Foundation
import Testing

@testable import PromptMasterMOSS

@MainActor
struct ManifestTests {
  @Test func manifestIsForBothSpellingsOfTheFamily() {
    let plugin = MossPlugin(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-manifest-\(UUID().uuidString)"), store: MossStore(storage: MemoryStorage()))
    #expect(plugin.manifest.families == ["moss_image", "mossImage"])
    #expect(MossPlugin.families == ["moss_image", "mossImage"])
    #expect(plugin.manifest.id == "com.exiztenz.dthub.promptmastermoss")
    #expect(plugin.manifest.name == "Prompt Master MOSS")
    // The same toolbar icon as the other Prompt Masters: plug-ins that do the same for different models never show together.
    #expect(plugin.manifest.symbol == "wand.and.stars")
  }
}
