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

  @Test func theDepthButtonsSayDepth() {
    for italian in [false, true] {
      for key in [L.Key.downloadModel, .redownload] {
        #expect(L.text(key, italian: italian).lowercased().contains("depth"), "\(key) \(italian)")
      }
      #expect(L.text(.downloadModel, italian: italian).contains("200 MB"))
    }
  }

  @Test func thePoseButtonsSayThePoseAndTheSize() {
    for italian in [false, true] {
      #expect(L.text(.downloadPoseModel, italian: italian).contains("64 MB"))
      #expect(!L.text(.redownloadPoseModel, italian: italian).isEmpty)
      #expect(!L.text(.poseModelDamaged, italian: italian).isEmpty)
    }
    #expect(L.text(.downloadPoseModel, italian: false).lowercased().contains("pose"))
    #expect(L.text(.downloadPoseModel, italian: true).lowercased().contains("posa"))
  }
}
