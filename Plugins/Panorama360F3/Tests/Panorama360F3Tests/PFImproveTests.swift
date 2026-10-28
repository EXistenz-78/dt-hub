import DTHubPluginKit
import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PFImproveTests {
  private func ready(description: String, images: Int = 1) -> PFState {
    let state = PFState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    state.apply(context: Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"}"#.utf8))
    let folder = TestImages.tempFolder()
    state.addImages((0..<images).map { TestImages.png(width: 80, height: 60, in: folder, name: "r\($0).png") })
    state.mutate { $0.description = description }
    return state
  }

  @Test func theAnswerReplacesTheDescriptionAndUndoBringsItBack() async {
    let state = ready(description: "old text")
    await state.improve { _, _, _ in .text("\"A misty lake at dawn, soft pink light.\"") }
    #expect(state.doc.description == "A misty lake at dawn, soft pink light.")
    #expect(state.previousDescription == "old text")
    state.undoImprove()
    #expect(state.doc.description == "old text" && state.previousDescription == nil)
  }

  @Test func theVisiblePicturesGoAlongAsFilesThatExistDuringTheCall() async {
    let state = ready(description: "", images: 2)
    var seen: [String] = []
    await state.improve { _, _, images in
      seen = images.filter { FileManager.default.fileExists(atPath: $0) }
      return .text("A quiet street at night.")
    }
    #expect(seen.count == 2)
    #expect(state.doc.description == "A quiet street at night.")
  }

  @Test func anAnswerThatHoldsTheTriggerOrAReferenceIsRefused() async {
    for bad in ["create a 360 hdr of a lake", "starting from <image 1> a lake"] {
      let state = ready(description: "lake")
      await state.improve { _, _, _ in .text(bad) }
      #expect(state.doc.description == "lake" && state.error != nil, "\(bad)")
    }
  }

  @Test func withNoTextAndNoPictureThereIsNothingToImprove() async {
    let state = ready(description: "  ", images: 0)
    var asked = false
    await state.improve { _, _, _ in
      asked = true
      return .text("x")
    }
    #expect(!asked && state.error != nil)
  }

  @Test func anItalianAnswerIsAskedAgainOnceAndThenRefused() async {
    let state = ready(description: "lago")
    var calls = 0
    await state.improve { _, _, _ in
      calls += 1
      return .text("Il lago è sul sfondo con la nebbia e le montagne")
    }
    #expect(calls == 2 && state.doc.description == "lago" && state.error != nil)
  }

  @Test func theRequestIsInEnglishAndNamesThePictures() {
    let request = PFPrompt.request(description: "lake", imageCount: 2, in: PFPrompt.folder(dataFolder: TestImages.tempFolder()))
    #expect(request.prompt.contains("lake") && request.prompt.contains("2"))
    #expect(!request.system.isEmpty)
  }
}
