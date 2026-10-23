import Foundation
import Testing

@testable import PromptMasterMOSS

struct ShufflerTests {
  @Test func picksAtMostThreeCategories_oneTermEach_neverANegative() {
    let data = MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))
    let catalog = MossCatalog(database: data.database, config: data.config)
    var generator = SystemRandomNumberGenerator()
    for mode in [StyleMode.photo, .art] {
      for _ in 0..<50 {
        let picked = MossShuffler.pick(catalog: catalog, mode: mode, using: &generator)
        #expect(picked.count <= 3 && !picked.isEmpty)
        let categories = picked.compactMap { catalog.category(ofTerm: $0)?.id }
        #expect(Set(categories).count == picked.count)
        #expect(!categories.contains("negative_terms"))
      }
    }
  }
}
