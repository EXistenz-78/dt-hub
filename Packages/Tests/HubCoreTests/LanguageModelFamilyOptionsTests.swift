import Testing

@testable import HubCore

struct LanguageModelFamilyOptionsTests {
  @Test func withoutACatalogItIsTheGuidesSortedByLabel() {
    let list = LanguageModelFamilyOptions.list(catalogFamilies: [])
    #expect(list.count == PromptGuides.all.count)
    #expect(list.map(\.label) == list.map(\.label).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    #expect(list.first { $0.key == "qwen_image_2.1" }?.label == "Qwen Image 2.1")
  }

  @Test func catalogFamiliesNotInTheGuidesAreAddedOnce() {
    let list = LanguageModelFamilyOptions.list(catalogFamilies: ["flux2_9b", "wan_v2.1", "wan_v2.1"])
    #expect(list.count == PromptGuides.all.count + 1)
    #expect(list.filter { $0.key == "wan_v2.1" }.map(\.label) == ["wan_v2.1"])
    #expect(list.filter { $0.key == "flux2_9b" }.count == 1)
  }
}
