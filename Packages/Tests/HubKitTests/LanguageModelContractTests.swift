import Testing

@testable import HubKit

struct LanguageModelContractTests {
  @Test func aModelIsIdentifiedByItsFolder() {
    let model = LanguageModelDescriptor(path: "/m/qwen", name: "qwen", sizeBytes: 10, supportsImages: false)
    #expect(model.id == "/m/qwen")
  }

  @Test func theRecommendedModelIsAHubRepositoryDownloadedIntoItsOwnFolder() {
    let parts = RecommendedLanguageModel.repository.split(separator: "/")
    #expect(parts.count == 2)
    #expect(RecommendedLanguageModel.folderName == RecommendedLanguageModel.repository)
    #expect(RecommendedLanguageModel.approximateBytes > 1_000_000_000)
  }
}
