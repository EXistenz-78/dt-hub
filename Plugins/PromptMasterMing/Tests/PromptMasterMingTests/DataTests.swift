import Foundation
import Testing

@testable import PromptMasterMing

@Suite("Data, prompts and strings")
struct DataTests {
  @Test func theEmbeddedDataIsCompleteAndConsistent() {
    let catalog = MingCatalog(database: Fixture.data.database, config: Fixture.data.config)
    #expect(Fixture.data.warnings.isEmpty)
    #expect(catalog.unknownCategories.isEmpty)
    #expect(!catalog.categories(mode: .art).contains { $0.id == "negative_terms" })
    let light = catalog.categories(mode: .photo).first { $0.id == "light_source" }!.terms[0]
    let color = catalog.categories(mode: .photo).first { $0.id == "color_palette" }!.terms[0]
    #expect(catalog.lightingTerms([light.id, color.id]) == [light.en])
    #expect(catalog.styleTerms([light.id, color.id]) == [color.en])
  }

  @Test func bothLanguagesHaveEveryString() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: false), "\(key) en")
      #expect(L.isDefined(key, italian: true), "\(key) it")
    }
  }

  @Test func thePromptsAreInstalledAndTheFamilyPromptWinsForComposing() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ming-prompts-\(UUID().uuidString)")
    MingPrompts.install(dataFolder: folder)
    let prompts = MingPrompts.folder(dataFolder: folder)
    #expect(MingPrompts.problems(in: prompts).isEmpty)
    #expect(MingPrompts.system(in: prompts).contains("image_style"))
    #expect(MingPrompts.composeSystem(familyPrompt: nil, in: prompts).contains("\"canvas_settings\""))
    #expect(MingPrompts.composeSystem(familyPrompt: "FAMILY RULES", in: prompts).hasPrefix("FAMILY RULES"))
  }
}
