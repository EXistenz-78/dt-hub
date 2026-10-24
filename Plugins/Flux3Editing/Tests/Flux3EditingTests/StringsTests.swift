import Testing

@testable import Flux3Editing

struct StringsTests {
  @Test func everyTextExistsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "missing Italian: \(key)")
      #expect(L.isDefined(key, italian: false), "missing English: \(key)")
    }
  }

  @Test func theWriteButtonIsCalledImprovePrompt() {
    #expect(L.text(.improvePrompt, italian: false) == "Improve prompt")
    #expect(L.text(.improvePrompt, italian: true) == "Migliora prompt")
    #expect(L.text(.improving, italian: false) == "Improving…")
    #expect(L.text(.improving, italian: true) == "Miglioro…")
  }
}
