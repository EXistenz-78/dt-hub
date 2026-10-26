import CoreGraphics
import Foundation
import Testing

@testable import Panorama360

/// What keeps the sphere view fluid: one render at a time with the latest request winning, no file written while a drag goes on, and no file
/// read again at every redraw.
@MainActor
@Suite("Smoothness")
struct PSSmoothTests {
  let size = CGSize(width: 1024, height: 768)

  func sphereState() -> PSState {
    let state = PSState(italian: false)
    state.switchProject(folder: PSModelsTests.folder())
    let s = Sticker(name: "s", file: "s.png")
    state.mutate { $0.stickers = [s]; $0.selectedID = s.id; $0.viewMode = .sphere }
    state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: s.id)
    return state
  }

  @Test func manyRequestsRenderAtMostAFewTimes() async {
    let state = sphereState()
    for _ in 0..<60 { state.refreshPreview(scale: 0.5) }
    await state.waitForPreviews()
    #expect(state.previewRenderCount >= 1 && state.previewRenderCount <= 3, "rendered \(state.previewRenderCount) times")
    #expect(state.preview != nil)
  }

  @Test func theLastRequestWins() async {
    let state = sphereState()
    state.refreshPreview(scale: 1)
    state.refreshPreview(scale: 0.5)
    state.refreshPreview(scale: 0.5)
    await state.waitForPreviews()
    #expect(state.preview?.width == 512 && state.preview?.height == 384)
  }

  @Test func aDragDoesNotWriteTheFileUntilItEnds() throws {
    let state = sphereState()
    let folder = try #require(state.projectFolder)
    state.spherePointerDown(at: CGPoint(x: 50, y: 50), size: size)
    for i in 1...20 { state.spherePointerDragged(to: CGPoint(x: 50 + 10 * Double(i), y: 50), size: size, shift: false) }
    #expect(PanoState.load(from: folder).camera == PSCamera(), "nothing written during the drag")
    #expect(state.doc.camera.yaw != 0)
    state.spherePointerUp()
    #expect(PanoState.load(from: folder).camera == state.doc.camera, "written when the drag ends")
  }

  @Test func aStickerDragIsWrittenOnlyAtTheEndToo() throws {
    let state = sphereState()
    let folder = try #require(state.projectFolder)
    state.spherePointerDown(at: CGPoint(x: 512, y: 384), size: size)
    state.spherePointerDragged(to: CGPoint(x: 600, y: 384), size: size, shift: false)
    #expect(PanoState.load(from: folder).stickers[0].yaw == 0)
    state.spherePointerUp()
    #expect(PanoState.load(from: folder).stickers[0].yaw == state.doc.stickers[0].yaw && state.doc.stickers[0].yaw != 0)
  }

  @Test func theZoomIsSavedAfterAShortWhile() async throws {
    let state = sphereState()
    let folder = try #require(state.projectFolder)
    for _ in 0..<10 { state.sphereZoom(by: 0.02) }
    #expect(PanoState.load(from: folder).camera.fov == 90, "not yet")
    // Soon, not at once: wait for it, as long as a busy machine needs.
    var saved = false
    for _ in 0..<200 {
      try await Task.sleep(for: .milliseconds(50))
      if PanoState.load(from: folder).camera == state.doc.camera {
        saved = true
        break
      }
    }
    #expect(saved && state.doc.camera.fov != 90)
  }

  @Test func switchingProjectFlushesTheSaveThatWasWaiting() throws {
    let state = sphereState()
    let first = try #require(state.projectFolder)
    state.sphereZoom(by: 0.2)
    let zoomed = state.doc.camera
    state.switchProject(folder: PSModelsTests.folder())
    #expect(PanoState.load(from: first).camera == zoomed)
    #expect(state.doc.camera == PSCamera())
  }

  @Test func thePatchSizeIsReadOnceNotAtEveryRedraw() throws {
    let state = PSState(italian: false)
    let patch = TestImages.file(TestImages.solid(1280, 960, 1, 2, 3), in: TestImages.tempFolder(), name: "retouch.png", type: "public.png")
    state.mutate {
      $0.lastCutout = PSCutoutMemory(yaw: 0, pitch: 0, fov: 70, width: 1280, height: 960, resultPathAtExtraction: "/r/a.png", patchPath: patch.path)
    }
    var reads = 0
    state.imageSizeReader = { url in
      reads += 1
      return PSCutout.pixelSize(of: url).map { ($0.width, $0.height) }
    }
    for _ in 0..<20 { #expect(state.putBackReason == nil) }
    #expect(reads == 1, "read \(reads) times")
    try FileManager.default.removeItem(at: patch)
    #expect(state.putBackReason == .patchMissing, "a file that is gone is noticed all the same")
  }
}
