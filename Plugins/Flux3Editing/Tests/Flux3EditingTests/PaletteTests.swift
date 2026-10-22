import Testing

@testable import Flux3Editing

struct PaletteTests {
  @Test func rotatesAfterEight() {
    #expect(EditPalette.color(index: 8) == EditPalette.color(index: 0))
    #expect(EditPalette.nsColor(index: 9) == EditPalette.nsColor(index: 1))
  }

  @Test func firstEightAreDistinct() {
    let colors = (0..<8).map { EditPalette.nsColor(index: $0) }
    #expect(Set(colors.map { "\($0.redComponent)-\($0.greenComponent)-\($0.blueComponent)" }).count == 8)
  }
}
