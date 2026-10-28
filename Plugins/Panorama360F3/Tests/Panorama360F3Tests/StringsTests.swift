import Testing

@testable import Panorama360F3

struct StringsTests {
  @Test func everyKeyHasItalianAndEnglishText() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian text")
      #expect(L.isDefined(key, italian: false), "\(key) has no English text")
      #expect(!L.text(key, italian: true).isEmpty && !L.text(key, italian: false).isEmpty)
    }
  }

  @Test func formatsKeepTheirPlaceholdersInBothLanguages() {
    #expect(L.format(.unreadableFile, "x.png", italian: true).contains("x.png"))
    #expect(L.format(.unreadableFile, "x.png", italian: false).contains("x.png"))
    #expect(L.format(.imageMissing, "y.png", italian: true).contains("y.png"))
    #expect(L.format(.imageMissing, "y.png", italian: false).contains("y.png"))
  }
}
