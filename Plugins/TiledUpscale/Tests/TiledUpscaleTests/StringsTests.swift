import Testing

@testable import TiledUpscale

@Suite("Strings")
struct StringsTests {
  @Test func everyWordIsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }

  @Test func formattedWordsKeepTheirNumbers() {
    for italian in [false, true] {
      #expect(L.format(.passes, 144, italian: italian).contains("144"))
      #expect(L.format(.finalSize, 4096, 3072, italian: italian).contains("4096"))
    }
  }
}
