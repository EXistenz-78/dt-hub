import Testing

@testable import SeamlessPattern

@Suite("Strings")
struct StringsTests {
  @Test func everyWordIsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }

  @Test func theTabSpeaksItalianOrEnglish() {
    #expect(L.text(.prepare, italian: true) == "Prepara Run · Seamless")
    #expect(L.text(.prepare, italian: false) == "Prepare Run · Seamless")
    #expect(L.mode(.both, italian: true) == "Entrambi")
  }

  @MainActor @Test func agentsAlwaysGetTheEnglishServerText() {
    #expect(SPState.customServerWarning == L.text(.needsServer, italian: false))
  }
}
