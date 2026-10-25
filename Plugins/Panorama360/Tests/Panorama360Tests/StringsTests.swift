import Testing

@testable import Panorama360

@Suite("Strings")
struct StringsTests {
  @Test func everyWordIsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }

  @Test func formattedWordsKeepTheirText() {
    for italian in [false, true] {
      #expect(L.format(.words, 12, italian: italian).contains("12"))
      #expect(L.format(.croppedPhoto, "a.jpg", italian: italian).contains("a.jpg"))
      #expect(L.format(.unreadableFile, "b.png", italian: italian).contains("b.png"))
    }
  }

  @Test func theTwoLanguagesDiffer() {
    #expect(L.text(.improve, italian: true) == "Migliora prompt" && L.text(.improve, italian: false) == "Improve prompt")
    #expect(L.text(.modeFast, italian: true) == "Veloce" && L.text(.modeFast, italian: false) == "Fast")
  }
}
