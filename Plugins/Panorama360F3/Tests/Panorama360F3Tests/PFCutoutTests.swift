import CoreGraphics
import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PFCutoutTests {
  @MainActor final class Recorder {
    var bodies: [[String: Any]] = []
    var contribute: PFContribute { { [self] body in bodies.append(body); return ["type": "ok"] } }
  }

  private func ready() -> PFState {
    let state = PFState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    state.apply(context: Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"}"#.utf8))
    return state
  }

  private func picture(_ width: Int, _ height: Int, name: String = "p.png") -> URL {
    TestImages.writePNG(TestImages.coordinates(width: width, height: height), to: TestImages.tempFolder().appendingPathComponent(name))
  }

  /// A state that shows a 512×256 panorama and has taken a 0.25 MP cutout (512×384) from it.
  private func extracted() throws -> (state: PFState, panorama: URL) {
    let state = ready()
    let panorama = picture(512, 256)
    state.dropPictures([panorama])
    state.mutate { $0.cutoutMegapixels = 0.25 }
    state.camera = PSCamera(yaw: 30, pitch: 10, fov: 80)
    _ = try state.extractCutout()
    return (state, panorama)
  }

  // MARK: the pure rules

  @Test func theSizeIsExactlyFourToThreeAndFollowsTheMegapixels() {
    #expect(PFCutout.size(megapixels: 1.0) == (1280, 960))
    #expect(PFCutout.size(megapixels: 0.25) == (512, 384))
    #expect(PFCutout.size(megapixels: 4.0) == (2304, 1728))
    #expect(PFCutout.size(megapixels: 99) == (2304, 1728) && PFCutout.size(megapixels: 0) == (512, 384))
  }

  @Test func theMontageIsEnlargedSoThatTheRetouchKeepsItsPixels() {
    // 1280 px over 90° need π·1280/tan(45°) ≈ 4021 px of panorama width, rounded up to a multiple of 128.
    #expect(PFCutout.montageSize(background: (2048, 1024), patchWidth: 1280, fov: 90) == (4096, 2048))
    #expect(PFCutout.montageSize(background: (512, 256), patchWidth: 512, fov: 80) == (1920, 960))
  }

  @Test func theMontageIsNeverSmallerThanThePanoramaAndNeverAboveTheCap() {
    #expect(PFCutout.montageSize(background: (4096, 2048), patchWidth: 512, fov: 90) == (4096, 2048))
    #expect(PFCutout.montageSize(background: (2048, 1024), patchWidth: 256, fov: 90) == (2048, 1024))
    #expect(PFCutout.montageSize(background: (2048, 1024), patchWidth: 2304, fov: 20) == (8192, 4096), "the cap is 8192 px wide")
    #expect(PFCutout.montageSize(background: (9000, 4500), patchWidth: 2304, fov: 20) == (9000, 4500), "a panorama already above the cap is kept")
  }

  @Test func aPanoramaThatIsNotTwoToOneKeepsItsProportionWhenEnlarged() {
    let size = PFCutout.montageSize(background: (3000, 1000), patchWidth: 1280, fov: 90)
    #expect(size.0 == 4096 && size.1 == 1365)
  }

  @Test func putBackReasonsInOrder() {
    let taken = PFCutoutMemory(yaw: 0, pitch: 0, fov: 90, width: 512, height: 384, resultPathAtExtraction: "/r/a.png", patchPath: nil)
    let sizes: [String: (Int, Int)] = ["/r/b.png": (512, 384), "/r/odd.png": (400, 400)]
    let size: (URL) -> (Int, Int)? = { sizes[$0.path] }
    #expect(PFCutout.putBackReason(memory: nil, lastResult: nil, imageSize: size) == .noCutout)
    #expect(PFCutout.putBackReason(memory: taken, lastResult: URL(fileURLWithPath: "/r/a.png"), imageSize: size) == .noPatch)
    #expect(PFCutout.putBackReason(memory: taken, lastResult: URL(fileURLWithPath: "/r/b.png"), imageSize: size) == nil)
    #expect(PFCutout.putBackReason(memory: taken, lastResult: URL(fileURLWithPath: "/r/gone.png"), imageSize: size) == .patchMissing)
    #expect(PFCutout.putBackReason(memory: taken, lastResult: URL(fileURLWithPath: "/r/odd.png"), imageSize: size) == .wrongProportion)
    var used = taken
    used.patchPath = "/r/b.png"
    #expect(PFCutout.putBackReason(memory: used, lastResult: URL(fileURLWithPath: "/r/a.png"), imageSize: size) == nil, "the retouch already used stays")
  }

  // MARK: extracting

  @Test func extractDrawsTheViewAndRemembersWhereItWasTaken() throws {
    let (state, panorama) = try extracted()
    #expect(state.cutoutImage?.width == 512 && state.cutoutImage?.height == 384)
    let memory = try #require(state.doc.lastCutout)
    #expect(memory.yaw == 30 && memory.pitch == 10 && memory.fov == 80 && memory.width == 512 && memory.height == 384)
    #expect(memory.resultPathAtExtraction == panorama.path && memory.patchPath == nil)
  }

  @Test func extractWithNoResultThrows() {
    let state = ready()
    #expect(throws: PFCutoutError.noResult) { try state.extractCutout() }
  }

  @Test func theMegapixelsAndTheMemorySurviveAReload() throws {
    let (state, _) = try extracted()
    let project = try #require(state.projectFolder)
    let other = PFState(italian: false)
    other.switchProject(folder: project)
    #expect(other.doc.cutoutMegapixels == 0.25 && other.doc.lastCutout?.width == 512)
  }

  // MARK: sending

  @Test func asAStartImageItCarriesTheCutoutSizeToo() async throws {
    let (state, _) = try extracted()
    let recorder = Recorder()
    await state.sendCutoutAsStartImage(contribute: recorder.contribute)
    let body = try #require(recorder.bodies.first)
    let start = try #require(body["startImage"] as? [String: Any])
    #expect(FileManager.default.fileExists(atPath: try #require(start["path"] as? String)))
    let fields = try #require(body["fields"] as? [String: Any])
    #expect(fields["width"] as? Int == 512 && fields["height"] as? Int == 384)
  }

  @Test func asAMoodboardPictureItGoesToTheAppsMoodboard() async throws {
    let (state, _) = try extracted()
    let recorder = Recorder()
    await state.addCutoutToMoodboard(contribute: recorder.contribute)
    let entries = try #require(recorder.bodies.first?["moodboard"] as? [[String: Any]])
    #expect(FileManager.default.fileExists(atPath: try #require(entries.first?["path"] as? String)))
  }

  @Test func sendingWithNoCutoutSaysSoAndSendsNothing() async {
    let state = ready()
    let recorder = Recorder()
    await state.sendCutoutAsStartImage(contribute: recorder.contribute)
    await state.addCutoutToMoodboard(contribute: recorder.contribute)
    #expect(recorder.bodies.isEmpty && state.error != nil)
  }

  @Test func saveWritesAPNGOfTheCutout() throws {
    let (state, _) = try extracted()
    let url = TestImages.tempFolder().appendingPathComponent("cut.png")
    try state.saveCutout(to: url)
    #expect(TestImages.size(of: url)?.width == 512 && TestImages.size(of: url)?.height == 384)
  }

  @Test func savingWithNoCutoutThrows() {
    #expect(throws: PFCutoutError.nothingExtracted) { try ready().saveCutout(to: TestImages.tempFolder().appendingPathComponent("x.png")) }
  }

  // MARK: putting it back

  @Test func putBackIsOffUntilThereIsARetouch() throws {
    #expect(ready().putBackReason == .noCutout)
    let (state, _) = try extracted()
    #expect(state.putBackReason == .noPatch && state.putBackInPanoramaReason == .noPatch)
  }

  @Test func putBackInPanoramaMakesAMontageForTheResults() async throws {
    let (state, panorama) = try extracted()
    let patch = picture(512, 384, name: "retouch.png")
    state.apply(context: Data(#"{"type":"context","tempFolder":"/tmp/x","lastResult":{"path":"\#(patch.path)","name":"r.png"}}"#.utf8))
    #expect(state.putBackReason == nil && state.putBackInPanoramaReason == nil)
    let recorder = Recorder()
    await state.putBackInPanorama(contribute: recorder.contribute)
    #expect(state.error == nil)
    let result = try #require(recorder.bodies.first?["result"] as? [String: Any])
    let path = try #require(result["path"] as? String)
    let size = try #require(TestImages.size(of: URL(fileURLWithPath: path)))
    #expect(size.width == 1920 && size.height == 960, "the montage is the panorama enlarged so that the retouch keeps its pixels")
    #expect((result["description"] as? String)?.contains("yaw") == true)
    #expect(state.doc.lastCutout?.patchPath == patch.path)
    #expect(FileManager.default.fileExists(atPath: panorama.path))
  }

  @Test func putBackInPanoramaIsOffWhenThePanoramaIsGone() throws {
    let (state, panorama) = try extracted()
    let patch = picture(512, 384, name: "retouch.png")
    state.apply(context: Data(#"{"type":"context","tempFolder":"/tmp/x","lastResult":{"path":"\#(patch.path)","name":"r.png"}}"#.utf8))
    try FileManager.default.removeItem(at: panorama)
    #expect(state.putBackInPanoramaReason == .panoramaMissing)
  }
}
