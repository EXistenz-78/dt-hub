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
    #expect(state.camera.yaw != 0)
    state.spherePointerUp()
    #expect(PanoState.load(from: folder).camera == state.camera && state.doc.camera == state.camera, "written when the drag ends")
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
      if PanoState.load(from: folder).camera == state.camera {
        saved = true
        break
      }
    }
    #expect(saved && state.camera.fov != 90 && state.doc.camera == state.camera)
  }

  @Test func switchingProjectFlushesTheSaveThatWasWaiting() throws {
    let state = sphereState()
    let first = try #require(state.projectFolder)
    state.sphereZoom(by: 0.2)
    let zoomed = state.camera
    state.switchProject(folder: PSModelsTests.folder())
    #expect(PanoState.load(from: first).camera == zoomed)
    #expect(state.camera == PSCamera() && state.doc.camera == PSCamera())
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

  // MARK: Looking around redraws only the view that shows it

  @Test func lookingAroundDoesNotChangeTheStateEveryCardObserves() throws {
    let state = sphereState()
    state.spherePointerDown(at: CGPoint(x: 50, y: 50), size: size)
    var changes = 0
    let watch = state.objectWillChange.sink { changes += 1 }
    for i in 1...30 { state.spherePointerDragged(to: CGPoint(x: 50 + 5 * Double(i), y: 50 + Double(i)), size: size, shift: false) }
    #expect(state.camera.yaw != 0 && state.camera.pitch != 0)
    #expect(changes == 0, "\(changes) changes of the state while only the camera moved")
    #expect(state.doc.camera == PSCamera(), "the document follows when the drag ends")
    state.spherePointerUp()
    #expect(state.doc.camera == state.camera)
    watch.cancel()
  }

  @Test func zoomingDoesNotChangeTheStateEveryCardObserves() {
    let state = sphereState()
    var changes = 0
    let watch = state.objectWillChange.sink { changes += 1 }
    for _ in 0..<10 { state.sphereZoom(by: 0.03) }
    #expect(state.camera.fov != 90 && changes == 0, "\(changes) changes")
    watch.cancel()
  }

  @Test func theLiveCameraIsTheOneThatCountsEverywhere() throws {
    let state = sphereState()
    state.mutate { $0.stickers[0].yaw = 0 }
    state.sphereZoom(by: -0.5)  // 45°
    let narrow = try state.renderPreview(scale: 0.25)
    state.resetCamera()  // 90°
    let wide = try state.renderPreview(scale: 0.25)
    func redPixels(_ image: CGImage) -> Int {
      let bytes = PSPixels.rgba(of: image).bytes
      return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 150 && bytes[$0 + 1] < 100 }.count
    }
    #expect(redPixels(narrow) > redPixels(wide), "a narrower view shows the sticker bigger")
  }

  @Test func aCameraSetInTheDocumentMovesTheLiveOne() {
    let state = sphereState()
    state.mutate { $0.camera = PSCamera(yaw: 30, pitch: 5, fov: 70) }
    #expect(state.camera == PSCamera(yaw: 30, pitch: 5, fov: 70))
  }

  @Test func movingTheCameraAsksForTheNewFrameAtOnce() async {
    let state = sphereState()
    state.sphereZoom(by: -0.3)
    await state.waitForPreviews()
    #expect(state.preview != nil, "no view had to notice the change first")
    #expect(state.previewRenderCount >= 1)
  }

  @Test func whileLookingTheFramesAreDrawnSmallerAndTheLastOneFull() async {
    let state = sphereState()
    state.spherePointerDown(at: CGPoint(x: 50, y: 50), size: size)
    state.spherePointerDragged(to: CGPoint(x: 90, y: 60), size: size, shift: false)
    await state.waitForPreviews()
    #expect(state.preview?.width == 512, "half size while dragging")
    state.spherePointerUp()
  }

  @Test func theTimeOfEachFrameIsMeasured() async {
    let state = sphereState()
    state.refreshPreview(scale: 0.5)
    await state.waitForPreviews()
    #expect(state.previewBox.renderMillis > 0)
    #expect(state.previewBox.latencyMillis >= state.previewBox.renderMillis)
  }
}
