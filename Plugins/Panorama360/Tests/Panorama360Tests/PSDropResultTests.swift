import CoreGraphics
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("A picture dropped on the result view")
struct PSDropResultTests {
  func context(_ url: URL?) -> Data {
    let last = url.map { #","lastResult":{"path":"\#($0.path)","name":"\#($0.lastPathComponent)"}"# } ?? ""
    return Data(#"{"type":"context","tempFolder":"/t"\#(last)}"#.utf8)
  }

  func picture(_ w: Int, _ h: Int, _ r: UInt8 = 10, name: String = "p.png") -> URL {
    TestImages.file(TestImages.solid(w, h, r, 120, 200), in: TestImages.tempFolder(), name: name, type: "public.png")
  }

  func state(result: URL?) -> PSState {
    let state = PSState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    state.apply(context: context(result))
    return state
  }

  @Test func theDroppedPictureBecomesTheResultShown() {
    let shown = state(result: picture(256, 128, 1, name: "a.png"))
    let dropped = picture(512, 256, 2, name: "b.png")
    shown.dropResult(from: [dropped])
    #expect(shown.lastResultPath == dropped.path)
    #expect(shown.resultImage?.width == 512)
    #expect(shown.doc.source == .result && shown.effectiveSource == .result)
    #expect(shown.error == nil)
  }

  @Test func itWorksWithoutAnyResultYet() {
    let s = state(result: nil)
    let dropped = picture(512, 256)
    s.dropResult(from: [dropped])
    #expect(s.lastResultPath == dropped.path && s.effectiveSource == .result)
  }

  @Test func theSameContextAgainDoesNotUndoTheDrop() {
    let current = picture(256, 128, 1, name: "a.png")
    let s = state(result: current)
    let dropped = picture(512, 256, 2, name: "b.png")
    s.dropResult(from: [dropped])
    s.apply(context: context(current))  // the app tells about the same result again (a context is sent for many reasons)
    #expect(s.lastResultPath == dropped.path)
  }

  @Test func aNewResultFromTheAppReplacesTheDrop() {
    let s = state(result: picture(256, 128, 1, name: "a.png"))
    s.dropResult(from: [picture(512, 256, 2, name: "b.png")])
    let newer = picture(1024, 512, 3, name: "c.png")
    s.apply(context: context(newer))
    #expect(s.lastResultPath == newer.path && s.resultImage?.width == 1024)
  }

  @Test func openingAnotherProjectDropsIt() {
    let current = picture(256, 128, 1, name: "a.png")
    let s = state(result: current)
    s.dropResult(from: [picture(512, 256, 2, name: "b.png")])
    s.switchProject(folder: TestImages.tempFolder())
    #expect(s.lastResultPath == current.path, "back to the result the app knows")
  }

  @Test func aFileThatCannotBeReadChangesNothingAndSaysSo() throws {
    let current = picture(256, 128, 1, name: "a.png")
    let s = state(result: current)
    let bad = TestImages.tempFolder().appendingPathComponent("not-a-picture.png")
    try Data("nope".utf8).write(to: bad)
    s.dropResult(from: [bad])
    #expect(s.lastResultPath == current.path)
    #expect(s.error?.contains("not-a-picture.png") == true)
  }

  @Test func theFirstReadablePictureOfSeveralIsTaken() throws {
    let s = state(result: nil)
    let bad = TestImages.tempFolder().appendingPathComponent("bad.png")
    try Data("nope".utf8).write(to: bad)
    let good = picture(512, 256, 5, name: "good.png")
    s.dropResult(from: [bad, good])
    #expect(s.lastResultPath == good.path)
  }

  @Test func theSeamButtonLooksAtTheDroppedPicture() {
    let s = state(result: picture(1000, 1024, 1, name: "square-ish.png"))
    #expect(s.seamReason == .notTwoToOne)
    s.dropResult(from: [picture(1024, 512, 2, name: "pano.png")])
    #expect(s.seamReason == nil)
  }
}
