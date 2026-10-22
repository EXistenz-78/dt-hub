import Testing

@testable import Flux3Editing

struct StringsTests {
  @Test func everyTextExistsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "missing Italian: \(key)")
      #expect(L.isDefined(key, italian: false), "missing English: \(key)")
    }
  }
}
