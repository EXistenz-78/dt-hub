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

  /// A state that shows a 512×256 panorama and has taken a cutout (512×384, the real resolution rounded up) from it.
  private func extracted() throws -> (state: PFState, panorama: URL) {
    let state = ready()
    let panorama = picture(512, 256)
    state.dropPictures([panorama])
    state.camera = PSCamera(yaw: 30, pitch: 10, fov: 80)
    _ = try state.extractCutout()
    return (state, panorama)
  }

  // MARK: the pure rules

  @Test func theCutoutKeepsTheRealResolutionAndItsSidesAreMultiplesOf64() {
    // 2048 px at 90°: 651.9 × 489.0 pixels across the view; each side is extended to the next multiple of 64 and the field of view widens with it
    // (more picture, the same pixels per degree), so nothing is stretched.
    let a = PFCutout.cutoutFrame(panoramaWidth: 2048, fov: 90)
    #expect(a.width == 704 && a.height == 512)
    #expect(abs(a.fov - 94.4) < 0.1)
    let b = PFCutout.cutoutFrame(panoramaWidth: 4096, fov: 90)
    #expect(b.width == 1344 && b.height == 1024)
    #expect(abs(b.fov - 91.7) < 0.1)
  }

  @Test func theDensityOfTheCutoutEqualsTheDensityOfThePanorama() {
    for (width, fov) in [(2048, 90.0), (4096, 70.0), (3072, 110.0), (6144, 85.0)] {
      let frame = PFCutout.cutoutFrame(panoramaWidth: width, fov: fov)
      let pixelsPerTan = Double(frame.width) / (2 * tan(frame.fov * .pi / 360))
      let panoramaPerTan = Double(width) / (2 * .pi)
      #expect(abs(pixelsPerTan - panoramaPerTan) / panoramaPerTan < 0.001, "width \(width), fov \(fov)")
      #expect(frame.width % 64 == 0 && frame.height % 64 == 0)
    }
  }

  @Test func aSmallOrHugeViewKeepsItsFieldOfViewAndTheSizeLimits() {
    let small = PFCutout.cutoutFrame(panoramaWidth: 2048, fov: 60)
    #expect(small.width == 512 && small.height == 384 && small.fov == 60, "never below 512 × 384")
    let huge = PFCutout.cutoutFrame(panoramaWidth: 8192, fov: 150)
    #expect(huge.width == 4096 && huge.height == 3072 && huge.fov == 150, "never above 4096 × 3072")
  }

  @Test func theRetouchIsBroughtToThePixelDensityOfThePanorama() {
    #expect(PFCutout.patchDensityWidth(panoramaWidth: 2048, fov: 90) == 652)
    #expect(PFCutout.patchDensityWidth(panoramaWidth: 4096, fov: 60) == 753)
    // The frame of a cutout has exactly this density: nothing is squeezed when it is put back.
    let frame = PFCutout.cutoutFrame(panoramaWidth: 2048, fov: 90)
    #expect(PFCutout.patchDensityWidth(panoramaWidth: 2048, fov: frame.fov) == frame.width)
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

  @Test func theMemoryOfTheCutoutSurvivesAReload() throws {
    let (state, _) = try extracted()
    let project = try #require(state.projectFolder)
    let other = PFState(italian: false)
    other.switchProject(folder: project)
    #expect(other.doc.lastCutout?.width == 512)
  }

  // MARK: sending

  @Test func theStartImageBodyAsksForHiResOnlyWhenASideIsAbove2048() {
    let small = PFCutoutActions.startImageBody(file: URL(fileURLWithPath: "/t/c.png"), width: 1536, height: 1152)
    #expect((small["fields"] as? [String: Any])?["highRes"] == nil)
    let big = PFCutoutActions.startImageBody(file: URL(fileURLWithPath: "/t/c.png"), width: 3072, height: 2304)
    let fields = big["fields"] as? [String: Any]
    #expect(fields?["width"] as? Int == 3072 && fields?["height"] as? Int == 2304 && fields?["highRes"] as? Bool == true)
  }

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
    #expect(size.width == 512 && size.height == 256, "the montage has the size of the panorama it was taken from")
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
