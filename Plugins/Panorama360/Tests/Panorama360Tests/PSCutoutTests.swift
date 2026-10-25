import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Panorama360

@MainActor
@Suite("Cutout")
struct PSCutoutTests {
  func file(_ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8), name: String = "p.png") -> URL {
    TestImages.file(TestImages.solid(w, h, rgb.0, rgb.1, rgb.2), in: TestImages.tempFolder(), name: name, type: "public.png")
  }

  func context(_ url: URL?) -> Data {
    let last = url.map { #","lastResult":{"path":"\#($0.path)","name":"\#($0.lastPathComponent)"}"# } ?? ""
    return Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"\#(last)}"#.utf8)
  }

  func readyState(result: URL? = nil) -> PSState {
    let state = PSState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    state.apply(context: context(result))
    let s = Sticker(name: "s", file: "s.png", yaw: 20, hfov: 60)
    state.mutate { $0.stickers = [s]; $0.selectedID = s.id; $0.viewMode = .sphere; $0.camera = PSCamera(yaw: 20, pitch: 0, fov: 70) }
    state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: s.id)
    return state
  }

  func size(of url: URL) -> (Int, Int)? { PSCutout.pixelSize(of: url).map { ($0.width, $0.height) } }

  @Test func theCutoutSizeIsFourByThreeInMultiplesOf64() {
    for (mp, expected) in [(1.0, (1152, 896)), (0.25, (576, 448)), (4.0, (2304, 1728))] {
      let s = PSCutout.size(megapixels: mp)
      #expect(s.width == expected.0 && s.height == expected.1, "\(mp) MP → \(s)")
      #expect(s.width % 64 == 0 && s.height % 64 == 0)
      #expect(abs(Double(s.width) / Double(s.height) - 4.0 / 3.0) < 0.06)
    }
    #expect(PSCutout.size(megapixels: 0).width == PSCutout.size(megapixels: 0.25).width)
    #expect(PSCutout.size(megapixels: 99).width == PSCutout.size(megapixels: 4).width)
  }

  @Test func extractRendersTheViewAtThatSizeAndRemembersThePose() throws {
    let result = file(256, 128, (10, 120, 200), name: "r.png")
    let state = readyState(result: result)
    state.mutate { $0.cutoutMegapixels = 0.25 }
    let image = try state.extractCutout()
    #expect(image.width == 576 && image.height == 448)
    #expect(TestImages.pixel(image, 288, 224).r > 150, "the sticker is in the middle of the view")
    let memory = try #require(state.doc.lastCutout)
    #expect(memory.yaw == 20 && memory.pitch == 0 && memory.fov == 70 && memory.width == 576 && memory.height == 448)
    #expect(memory.resultPathAtExtraction == result.path && memory.patchPath == nil)
    #expect(state.cutoutImage != nil)
  }

  @Test func theExtractionOfTheResultSamplesThePanorama() throws {
    let state = readyState(result: file(256, 128, (10, 120, 200)))
    state.setSource(.result)
    let image = try state.extractCutout()
    let p = TestImages.pixel(image, 100, 100)
    #expect(abs(p.r - 10) <= 2 && abs(p.g - 120) <= 2 && abs(p.b - 200) <= 2, "\(p)")
  }

  @Test func startImageAndMoodboardBodiesNameThePng() throws {
    let url = URL(fileURLWithPath: "/tmp/c.png")
    let start = PSCutoutActions.startImageBody(file: url)
    let image = try #require(start["startImage"] as? [String: Any])
    #expect(image["path"] as? String == "/tmp/c.png" && image["name"] as? String == "panorama-360-cutout.png")
    let mood = PSCutoutActions.moodboardBody(file: url)
    let list = try #require(mood["moodboard"] as? [[String: Any]])
    #expect(list.count == 1 && list[0]["path"] as? String == "/tmp/c.png")
  }

  @Test func theActionsSendTheExtractedPicture() async throws {
    let state = readyState()
    _ = try state.extractCutout()
    nonisolated(unsafe) var bodies: [[String: Any]] = []
    let send: PSContribute = { body in
      bodies.append(body)
      return ["type": "ok"]
    }
    await state.sendCutoutAsStartImage(contribute: send)
    await state.addCutoutToMoodboard(contribute: send)
    #expect(bodies.count == 2 && bodies[0]["startImage"] != nil && bodies[1]["moodboard"] != nil)
    let path = try #require((bodies[0]["startImage"] as? [String: Any])?["path"] as? String)
    #expect(size(of: URL(fileURLWithPath: path))! == (1152, 896))
  }

  // MARK: Put back — when it is allowed

  @Test func putBackIsOffWithoutACutoutOrWithTheSameResult() {
    let r = URL(fileURLWithPath: "/r/a.png")
    let memory = PSCutoutMemory(yaw: 0, pitch: 0, fov: 70, width: 1152, height: 896, resultPathAtExtraction: "/r/a.png", patchPath: nil)
    #expect(PSCutout.putBackReason(memory: nil, lastResult: r, imageSize: { _ in (1152, 896) }) == .noCutout)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: nil, imageSize: { _ in (1152, 896) }) == .noPatch)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: r, imageSize: { _ in (1152, 896) }) == .noPatch)
  }

  @Test func putBackIsOffForAnotherProportion() {
    let memory = PSCutoutMemory(yaw: 0, pitch: 0, fov: 70, width: 1152, height: 896, resultPathAtExtraction: "/r/a.png", patchPath: nil)
    let b = URL(fileURLWithPath: "/r/b.png")
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (2048, 1024) }) == .wrongProportion)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (1152, 896) }) == nil)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (1175, 896) }) == nil, "within 2 %")
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (1280, 896) }) == .wrongProportion)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in nil }) == .patchMissing)
  }

  @Test func putBackStaysAvailableOnTheSameRetouchAfterTheMontage() {
    var memory = PSCutoutMemory(yaw: 0, pitch: 0, fov: 70, width: 1152, height: 896, resultPathAtExtraction: "/r/a.png", patchPath: "/r/retouch.png")
    let montage = URL(fileURLWithPath: "/r/montage.png")
    // The newest result is now the 2:1 montage; the retouch (4:3) is the one that counts.
    let sizes: (URL) -> (Int, Int)? = { $0.lastPathComponent == "retouch.png" ? (1152, 896) : (2048, 1024) }
    #expect(PSCutout.putBackReason(memory: memory, lastResult: montage, imageSize: sizes) == nil)
    #expect(PSCutout.patch(memory: memory, lastResult: montage)?.path == "/r/retouch.png")
    memory.patchPath = nil
    #expect(PSCutout.patch(memory: memory, lastResult: montage)?.path == "/r/montage.png")
  }

  // MARK: Put back — what it does

  @Test func putBackAsStickerPlacesThePatchAtThePoseOfTheExtraction() throws {
    let state = readyState(result: file(256, 128, (10, 120, 200), name: "r.png"))
    _ = try state.extractCutout()
    let retouch = file(1152, 896, (30, 200, 60), name: "retouch.png")
    state.apply(context: context(retouch))
    #expect(state.putBackReason == nil)
    state.mutate { $0.viewMode = .sphere }
    state.putBackAsSticker()
    #expect(state.error == nil && state.doc.stickers.count == 2)
    let placed = state.doc.stickers[1]
    #expect(placed.yaw == 20 && placed.pitch == 0 && placed.hfov == 70 && placed.rot == 0)
    #expect(state.doc.selectedID == placed.id && state.doc.viewMode == .plane && state.doc.source == .canvas)
    #expect(FileManager.default.fileExists(atPath: state.projectFolder!.appendingPathComponent(placed.file).path))
    #expect(state.doc.lastCutout?.patchPath == retouch.path)
  }

  @Test func putBackInThePanoramaComposesAndFilesTheMontage() async throws {
    let panorama = file(256, 128, (10, 120, 200), name: "r.png")
    let state = readyState(result: panorama)
    _ = try state.extractCutout()
    state.mutate { $0.camera = PSCamera(yaw: 20, pitch: 0, fov: 70) }
    let retouch = file(1152, 896, (200, 30, 30), name: "retouch.png")
    state.apply(context: context(retouch))
    nonisolated(unsafe) var body: [String: Any] = [:]
    await state.putBackInPanorama { sent in
      body = sent
      return ["type": "ok"]
    }
    #expect(state.error == nil)
    let result = try #require(body["result"] as? [String: Any])
    let path = try #require(result["path"] as? String)
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 256 && image.height == 128)
    // The patch sits at yaw 20 (u = 0.5 + 20/360), the panorama colour is kept far from it.
    let x = Int((0.5 + 20.0 / 360) * 256)
    #expect(TestImages.pixel(image, x, 64).r > 150 && TestImages.pixel(image, 10, 64).b > 150)
    #expect((result["description"] as? String)?.contains("FOV") == true)
    #expect(state.doc.lastCutout?.patchPath == retouch.path)
  }

  @Test func aFailedContributeShowsTheProblemsAndKeepsThePatchFree() async throws {
    let state = readyState(result: file(256, 128, (10, 120, 200), name: "r.png"))
    _ = try state.extractCutout()
    state.apply(context: context(file(1152, 896, (200, 30, 30), name: "retouch.png")))
    await state.putBackInPanorama { _ in ["type": "ok", "problems": ["result: no model"]] }
    #expect(state.error?.contains("no model") == true && state.doc.lastCutout?.patchPath == nil)
  }

  @Test func putBackInThePanoramaNeedsAPanoramaToComposeOn() throws {
    let state = readyState()  // no result when the cutout was taken
    _ = try state.extractCutout()
    state.apply(context: context(file(1152, 896, (200, 30, 30), name: "retouch.png")))
    #expect(state.putBackReason == nil)
    #expect(state.putBackInPanoramaReason == .noPanorama)
  }

  @Test func aNewExtractionResetsThePatch() throws {
    let state = readyState(result: file(256, 128, (10, 120, 200), name: "r.png"))
    _ = try state.extractCutout()
    state.apply(context: context(file(1152, 896, (200, 30, 30), name: "retouch.png")))
    state.putBackAsSticker()
    #expect(state.doc.lastCutout?.patchPath != nil)
    state.mutate { $0.viewMode = .sphere }
    _ = try state.extractCutout()
    #expect(state.doc.lastCutout?.patchPath == nil)
  }

  @Test func theSaveWritesThePicture() throws {
    let state = readyState()
    _ = try state.extractCutout()
    let target = TestImages.tempFolder().appendingPathComponent("saved.png")
    try state.saveCutout(to: target)
    #expect(size(of: target)! == (1152, 896))
    let empty = PSState(italian: false)
    #expect(throws: PSCutoutError.nothingExtracted) { try empty.saveCutout(to: target) }
  }
}
