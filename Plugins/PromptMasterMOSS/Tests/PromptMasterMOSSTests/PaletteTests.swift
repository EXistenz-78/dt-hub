import SwiftUI
import Testing

@testable import PromptMasterMOSS

struct PaletteTests {
  @Test func theFiveLabelsHaveDistinctStableColors() {
    let hexes = MossLabel.allCases.map { MossPalette.hex(for: $0) }
    #expect(Set(hexes).count == 5)
    #expect(MossPalette.hex(for: .object) == "#3EC8C8" && MossPalette.hex(for: .subject) == "#FF7A7A")
    #expect(MossLabel.allCases.map { MossPalette.hex(for: $0) } == hexes)
  }
}
