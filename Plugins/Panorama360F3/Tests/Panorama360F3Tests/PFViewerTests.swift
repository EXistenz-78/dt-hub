import CoreGraphics
import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PFViewerTests {
  private func ready() -> PFState {
    let state = PFState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    state.apply(context: Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"}"#.utf8))
    return state
  }

  private func context(result: String?) -> Data {
    let last = result.map { #","lastResult":{"path":"\#($0)","name":"r.png"}"# } ?? ""
    return Data(#"{"type":"context","tempFolder":"/tmp/x"\#(last)}"#.utf8)
  }

  private func panorama(_ width: Int, _ height: Int, name: String = "p.png") -> URL {
    TestImages.writePNG(TestImages.coordinates(width: width, height: height), to: TestImages.tempFolder().appendingPathComponent(name))
  }

  @MainActor final class Recorder {
    var bodies: [[String: Any]] = []
    var contribute: PFContribute { { [self] body in bodies.append(body); return ["type": "ok"] } }
  }

  // MARK: opening

  @Test func theViewerIsClosedByDefault() {
    #expect(PFState(italian: false).doc.viewerOpen == false)
  }

  @Test func aNewResultInTheContextOpensTheViewerButTheSameOneDoesNotReopenIt() {
    let state = ready()
    let first = panorama(256, 128).path
    state.apply(context: context(result: first))
    #expect(state.doc.viewerOpen && state.shownPath == first)
    state.setViewerOpen(false)
    state.apply(context: context(result: first))
    #expect(!state.doc.viewerOpen, "the same result again does not reopen a viewer the user closed")
    let second = panorama(256, 128, name: "q.png").path
    state.apply(context: context(result: second))
    #expect(state.doc.viewerOpen && state.shownPath == second)
  }

  // MARK: dropping

  @Test func aDroppedPictureBecomesTheShownResult() {
    let state = ready()
    let dropped = panorama(256, 128)
    state.dropPictures([dropped])
    #expect(state.shownPath == dropped.path && state.resultImage?.width == 256)
    #expect(state.doc.viewerOpen)
    // A context for the same result as before does not take the dropped picture away; a different result does.
    state.apply(context: context(result: nil))
    #expect(state.shownPath == dropped.path)
    let newer = panorama(256, 128, name: "n.png").path
    state.apply(context: context(result: newer))
    #expect(state.shownPath == newer)
  }

  @Test func anUnreadableDropChangesNothingAndSaysSo() throws {
    let state = ready()
    let kept = panorama(256, 128)
    state.dropPictures([kept])
    let text = TestImages.tempFolder().appendingPathComponent("notes.txt")
    try Data("no".utf8).write(to: text)
    state.dropPictures([text])
    #expect(state.shownPath == kept.path)
    #expect(state.error?.contains("notes.txt") == true)
  }

  // MARK: the seam button

  @Test func seamReasonCoversNoResultUnreadableNotTwoToOneSizeAndTooBig() {
    let state = ready()
    #expect(state.seamReason == .noResult)
    state.apply(context: context(result: "/nowhere/missing.png"))
    #expect(state.seamReason == .unreadable)
    state.dropPictures([panorama(2048, 1000)])
    #expect(state.seamReason == .sizeNotMultipleOf64)
    state.dropPictures([panorama(2048, 1536)])
    #expect(state.seamReason == .notTwoToOne)
    state.dropPictures([panorama(256, 128)])
    #expect(state.seamReason == nil)
  }

  @Test func fixSeamProposesOnePassWithTheSeamPreset() async throws {
    let state = ready()
    state.dropPictures([panorama(256, 128)])
    let recorder = Recorder()
    await state.fixSeam(contribute: recorder.contribute)
    #expect(state.error == nil)
    let pipeline = try #require(recorder.bodies.first?["pipeline"] as? [String: Any])
    #expect(pipeline["guided"] as? Bool == true && pipeline["passes"] as? Int == 1)
    let estimate = try #require(pipeline["estimate"] as? [String: Any])
    #expect(estimate["preset"] as? String == "PANO F3 Seamfix")
    #expect((estimate["size"] as? [String: Any])?["width"] as? Int == 128)
    #expect(state.session != nil)
  }

  @Test func fixSeamWithAReasonProposesNothing() async {
    let state = ready()
    state.dropPictures([panorama(2048, 1536)])
    let recorder = Recorder()
    await state.fixSeam(contribute: recorder.contribute)
    #expect(recorder.bodies.isEmpty && state.error != nil && state.session == nil)
  }

  // MARK: looking around

  @Test func lookingAroundChangesTheCameraAndResetBringsItBack() {
    let state = ready()
    let before = state.camera
    state.lookAround(dx: 50, dy: 20, width: 500)
    #expect(state.camera.yaw != before.yaw && state.camera.pitch != before.pitch)
    state.zoom(by: -0.2)
    #expect(state.camera.fov < before.fov)
    state.resetCamera()
    #expect(state.camera == PSCamera())
  }

  @Test func theRendererDrawsTheViewOfAPanorama() throws {
    let view = try PSRendererFactory.make().renderView(
      .panorama(TestImages.coordinates(width: 512, height: 256)), camera: PSCamera(), width: 256, height: 192)
    #expect(view.width == 256 && view.height == 192)
  }

  @Test func thePreviewIsRenderedForTheShownResult() async {
    let state = ready()
    state.dropPictures([panorama(512, 256)])
    await state.renderPreview(width: 256, height: 192)
    #expect(state.preview?.width == 256 && state.preview?.height == 192)
  }
}
