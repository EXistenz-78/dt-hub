import Testing

@testable import PromptMasterF3

struct PaletteTests {
  @Test func rotatesAfterEight() {
    #expect(F3Palette.color(index: 8) == F3Palette.color(index: 0))
    #expect(F3Palette.nsColor(index: 9) == F3Palette.nsColor(index: 1))
  }

  @Test func firstEightAreDistinct() {
    let colors = (0..<8).map { F3Palette.nsColor(index: $0) }
    #expect(Set(colors.map { "\($0.redComponent)-\($0.greenComponent)-\($0.blueComponent)" }).count == 8)
  }
}
