import Testing

@testable import DepthPose

@Suite("Strings")
struct StringsTests {
  @Test func everyWordIsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }

  @Test func downloadingShowsThePercentage() {
    #expect(L.format(.downloading, 42, italian: false).contains("42"))
    #expect(L.format(.downloading, 42, italian: true).contains("42"))
  }

  /// The model is about 200 MB (Base, two functions): the button must not promise less.
  @Test func theDownloadButtonSaysTheRealSize() {
    for italian in [false, true] {
      #expect(L.text(.downloadModel, italian: italian).contains("200 MB"))
      #expect(!L.text(.downloadModel, italian: italian).contains("50 MB"))
    }
  }
}
