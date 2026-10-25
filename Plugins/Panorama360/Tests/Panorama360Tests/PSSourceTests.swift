import CoreGraphics
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Source and view")
struct PSSourceTests {
  func context(result: URL? = nil, path: String? = nil) -> Data {
    let p = path ?? result?.path
    let last = p.map { #","lastResult":{"path":"\#($0)","name":"\#(URL(fileURLWithPath: $0).lastPathComponent)"}"# } ?? ""
    return Data(#"{"type":"context","tempFolder":"/t"\#(last)}"#.utf8)
  }

  func picture(_ w: Int, _ h: Int, _ r: UInt8 = 10, name: String = "result.png") -> URL {
    TestImages.file(TestImages.solid(w, h, r, 120, 200), in: TestImages.tempFolder(), name: name, type: "public.png")
  }

  @Test func theContextBringsTheLastResult() {
    let state = PSState(italian: false)
    let url = picture(256, 128)
    state.apply(context: context(result: url))
    #expect(state.lastResultPath == url.path && state.resultImage?.width == 256)
    state.apply(context: context())
    #expect(state.lastResultPath == nil && state.resultImage == nil && state.resultNotice == nil)
  }

  @Test func withoutAResultTheSourceFallsBackToTheCanvas() {
    let state = PSState(italian: false)
    state.mutate { $0.source = .result; $0.viewMode = .sphere }
    state.apply(context: context())
    #expect(state.doc.source == .canvas && state.doc.viewMode == .sphere)
  }

  @Test func aResultThatIsThereKeepsTheChosenSource() {
    let state = PSState(italian: false)
    state.mutate { $0.source = .result }
    state.apply(context: context(result: picture(256, 128)))
    #expect(state.doc.source == .result && state.effectiveSource == .result)
  }

  @Test func aMissingOrUnreadableResultFileGivesANoticeAndTheCanvas() throws {
    let state = PSState(italian: false)
    state.mutate { $0.source = .result }
    state.apply(context: context(path: "/nowhere/gone.png"))
    #expect(state.resultImage == nil && state.resultNotice != nil && state.doc.source == .canvas)
    let broken = TestImages.tempFolder().appendingPathComponent("broken.png")
    try Data("not a picture".utf8).write(to: broken)
    state.apply(context: context(result: broken))
    #expect(state.resultImage == nil && state.resultNotice != nil)
  }

  @Test func aResultThatIsNotTwoToOneIsShownWithANotice() {
    let state = PSState(italian: false)
    state.apply(context: context(result: picture(100, 100)))
    #expect(state.resultImage != nil && state.resultNotice != nil)
    state.apply(context: context(result: picture(2048, 1024, name: "ok.png")))
    #expect(state.resultNotice == nil)
  }

  @Test func aNewResultReplacesTheOneShown() {
    let state = PSState(italian: false)
    state.apply(context: context(result: picture(256, 128, name: "a.png")))
    state.apply(context: context(result: picture(512, 256, 99, name: "b.png")))
    #expect(state.resultImage?.width == 512)
  }

  @Test func setSourceIgnoresTheResultWhenThereIsNone() {
    let state = PSState(italian: false)
    state.setSource(.result)
    #expect(state.doc.source == .canvas)
    state.apply(context: context(result: picture(256, 128)))
    state.setSource(.result)
    #expect(state.doc.source == .result)
    state.setView(.sphere)
    #expect(state.doc.viewMode == .sphere)
  }

  @Test func viewAndSourceAndCameraArePerProject() {
    let one = PSModelsTests.folder(), two = PSModelsTests.folder()
    let state = PSState(italian: false)
    state.switchProject(folder: one)
    state.mutate { $0.viewMode = .sphere; $0.source = .result; $0.camera = PSCamera(yaw: 30, pitch: 5, fov: 70) }
    state.switchProject(folder: two)
    #expect(state.doc.viewMode == .plane && state.doc.source == .canvas && state.doc.camera == PSCamera())
    state.switchProject(folder: one)
    #expect(state.doc.viewMode == .sphere && state.doc.source == .result && state.doc.camera == PSCamera(yaw: 30, pitch: 5, fov: 70))
  }

  @Test func theSphereAreaIsFourByThree() {
    #expect(abs(Double(PSSphereView.aspect) - 4.0 / 3.0) < 1e-12)
    #expect(PSState.sphereSize == CGSize(width: 1024, height: 768) && PSState.planeSize == CGSize(width: 1024, height: 512))
  }

  @Test func thePreviewHasTheSizeOfEachViewAndOfTheScale() throws {
    let state = PSState(italian: false)
    let s = Sticker(name: "s", file: "s.png")
    state.mutate { $0.stickers = [s] }
    state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: s.id)
    let plane = try state.renderPreview(scale: 1)
    #expect(plane.width == 1024 && plane.height == 512)
    state.setView(.sphere)
    let sphere = try state.renderPreview(scale: 1)
    #expect(sphere.width == 1024 && sphere.height == 768)
    let half = try state.renderPreview(scale: 0.5)
    #expect(half.width == 512 && half.height == 384)
    #expect(TestImages.pixel(sphere, 512, 384).r > 150, "the sticker is in front of the camera")
  }

  @Test func theResultSourceDrawsTheResultNotTheStickers() throws {
    let state = PSState(italian: false)
    let s = Sticker(name: "s", file: "s.png")
    state.mutate { $0.stickers = [s] }
    state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: s.id)
    state.apply(context: context(result: picture(256, 128, 10)))
    state.setView(.sphere)
    state.setSource(.result)
    let image = try state.renderPreview(scale: 1)
    let p = TestImages.pixel(image, 512, 384)
    #expect(abs(p.r - 10) <= 2 && abs(p.g - 120) <= 2 && abs(p.b - 200) <= 2, "\(p)")
  }

  @Test func aResultDeletedAfterItWasLoadedIsNoticedAtTheNextContext() throws {
    let state = PSState(italian: false)
    let url = picture(256, 128)
    state.apply(context: context(result: url))
    state.mutate { $0.source = .result }
    try FileManager.default.removeItem(at: url)
    state.apply(context: context(result: url))
    #expect(state.resultImage == nil && state.resultNotice != nil && state.doc.source == .canvas)
  }

  @Test func withTheResultChosenButNotThereTheCanvasIsWhatCountsEverywhere() {
    // A project saved with «Result» opened before the app has said which result there is (or in a project with none).
    let folder = PSModelsTests.folder()
    var saved = PanoState()
    saved.source = .result
    saved.viewMode = .sphere
    try? saved.save(to: folder)
    let state = PSState(italian: false)
    state.switchProject(folder: folder)
    #expect(state.doc.source == .result, "the choice is kept for when the result arrives")
    #expect(state.effectiveSource == .canvas)
    let s = Sticker(name: "s", file: "s.png")
    state.mutate { $0.stickers = [s]; $0.selectedID = s.id }
    state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: s.id)
    state.spherePointerDown(at: CGPoint(x: 512, y: 384), size: CGSize(width: 1024, height: 768))
    state.spherePointerDragged(to: CGPoint(x: 612, y: 384), size: CGSize(width: 1024, height: 768), shift: false)
    state.spherePointerUp()
    #expect(state.doc.stickers[0].yaw != 0, "editable: what is shown is the canvas")
  }
}
