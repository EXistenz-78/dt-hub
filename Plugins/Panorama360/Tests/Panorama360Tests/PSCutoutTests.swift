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

  @Test func theCutoutKeepsTheRealResolutionAndItsSidesAreMultiplesOf64() {
    // 2048 px at 90°: 651.9 × 489.0 pixels across the view; each side is extended to the next multiple of 64 and the field of view widens with it
    // (more picture, the same pixels per degree), so nothing is stretched.
    let a = PSCutout.cutoutFrame(panoramaWidth: 2048, fov: 90)
    #expect(a.width == 704 && a.height == 512)
    #expect(abs(a.fov - 94.4) < 0.1)
    let b = PSCutout.cutoutFrame(panoramaWidth: 4096, fov: 90)
    #expect(b.width == 1344 && b.height == 1024)
    #expect(abs(b.fov - 91.7) < 0.1)
  }

  @Test func theDensityOfTheCutoutEqualsTheDensityOfThePanorama() {
    for (width, fov) in [(2048, 90.0), (4096, 70.0), (3072, 110.0), (6144, 85.0)] {
      let frame = PSCutout.cutoutFrame(panoramaWidth: width, fov: fov)
      let pixelsPerTan = Double(frame.width) / (2 * tan(frame.fov * .pi / 360))
      let panoramaPerTan = Double(width) / (2 * .pi)
      #expect(abs(pixelsPerTan - panoramaPerTan) / panoramaPerTan < 0.001, "width \(width), fov \(fov)")
      #expect(frame.width % 64 == 0 && frame.height % 64 == 0)
    }
  }

  @Test func aSmallOrHugeViewKeepsItsFieldOfViewAndTheSizeLimits() {
    let small = PSCutout.cutoutFrame(panoramaWidth: 2048, fov: 60)
    #expect(small.width == 512 && small.height == 384 && small.fov == 60, "never below 512 × 384")
    let huge = PSCutout.cutoutFrame(panoramaWidth: 8192, fov: 150)
    #expect(huge.width == 4096 && huge.height == 3072 && huge.fov == 150, "never above 4096 × 3072")
  }

  @Test func theRetouchIsBroughtToThePixelDensityOfThePanorama() {
    #expect(PSCutout.patchDensityWidth(panoramaWidth: 2048, fov: 90) == 652)
    #expect(PSCutout.patchDensityWidth(panoramaWidth: 4096, fov: 60) == 753)
    let frame = PSCutout.cutoutFrame(panoramaWidth: 2048, fov: 90)
    #expect(PSCutout.patchDensityWidth(panoramaWidth: 2048, fov: frame.fov) == frame.width)
  }

  @Test func theCutoutOfTheResultIsTakenAtTheRealResolutionOfThePanoramaFile() throws {
    // 4400 px wide: the picture the tab shows is cut to 4096, the cutout must be read from the file at its own size.
    let state = readyState(result: file(4400, 2200, (10, 120, 200), name: "big.png"))
    state.setSource(.result)
    state.mutate { $0.camera = PSCamera(yaw: 0, pitch: 0, fov: 60) }
    let image = try state.extractCutout()
    #expect(image.width == 832 && image.height == 640, "from 4400 px, not from 4096")
    #expect(state.doc.lastCutout?.width == 832)
  }

  @Test func theCutoutOfTheCanvasIsTakenAtTheResolutionOfTheCanvas() throws {
    let state = readyState()
    state.mutate { $0.camera = PSCamera(yaw: 0, pitch: 0, fov: 90) }
    let image = try state.extractCutout()
    #expect(image.width == 704 && image.height == 512, "the canvas is 2048 px wide")
    let memory = try #require(state.doc.lastCutout)
    #expect(abs(memory.fov - 94.4) < 0.1, "the field of view that was really drawn")
  }

  @Test func extractRendersTheViewAtThatSizeAndRemembersThePose() throws {
    let result = file(256, 128, (10, 120, 200), name: "r.png")
    let state = readyState(result: result)
    let image = try state.extractCutout()
    #expect(image.width == 512 && image.height == 384)
    #expect(TestImages.pixel(image, 288, 224).r > 150, "the sticker is in the middle of the view")
    let memory = try #require(state.doc.lastCutout)
    #expect(memory.yaw == 20 && memory.pitch == 0 && memory.width == 512 && memory.height == 384)
    // 456.5 px across the view at 70° from the 2048 px canvas: rounded up to 512, so the field of view widens to match.
    #expect(abs(memory.fov - PSCutout.cutoutFrame(panoramaWidth: 2048, fov: 70).fov) < 0.001 && memory.fov > 70 && memory.fov < 80)
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
    let start = PSCutoutActions.startImageBody(file: url, width: 1280, height: 960)
    let image = try #require(start["startImage"] as? [String: Any])
    #expect(image["path"] as? String == "/tmp/c.png" && image["name"] as? String == "panorama-360-cutout.png")
    // The retouch RUN is made at the size of the cutout, not at the 2:1 size of the panorama.
    let fields = try #require(start["fields"] as? [String: Any])
    #expect(fields["width"] as? Int == 1280 && fields["height"] as? Int == 960)
    #expect(fields["highRes"] == nil, "HiRes only above 2048")
    #expect(fields["prompt"] == nil, "the prompt is the user's: the cutout does not write one")
    let mood = PSCutoutActions.moodboardBody(file: url)
    let list = try #require(mood["moodboard"] as? [[String: Any]])
    #expect(list.count == 1 && list[0]["path"] as? String == "/tmp/c.png")
  }

  @Test func aCutoutWithASideAbove2048AsksForHiRes() throws {
    let big = PSCutoutActions.startImageBody(file: URL(fileURLWithPath: "/t/c.png"), width: 3072, height: 2304)
    let fields = try #require(big["fields"] as? [String: Any])
    #expect(fields["width"] as? Int == 3072 && fields["height"] as? Int == 2304 && fields["highRes"] as? Bool == true)
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
    let sent = try #require(bodies[0]["fields"] as? [String: Any])
    #expect(sent["width"] as? Int == 512 && sent["height"] as? Int == 384)
    let path = try #require((bodies[0]["startImage"] as? [String: Any])?["path"] as? String)
    #expect(size(of: URL(fileURLWithPath: path))! == (512, 384))
  }

  // MARK: Put back — when it is allowed

  @Test func putBackIsOffWithoutACutoutOrWithTheSameResult() {
    let r = URL(fileURLWithPath: "/r/a.png")
    let memory = PSCutoutMemory(yaw: 0, pitch: 0, fov: 70, width: 1280, height: 960, resultPathAtExtraction: "/r/a.png", patchPath: nil)
    #expect(PSCutout.putBackReason(memory: nil, lastResult: r, imageSize: { _ in (1280, 960) }) == .noCutout)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: nil, imageSize: { _ in (1280, 960) }) == .noPatch)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: r, imageSize: { _ in (1280, 960) }) == .noPatch)
  }

  @Test func putBackIsOffForAnotherProportion() {
    let memory = PSCutoutMemory(yaw: 0, pitch: 0, fov: 70, width: 1280, height: 960, resultPathAtExtraction: "/r/a.png", patchPath: nil)
    let b = URL(fileURLWithPath: "/r/b.png")
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (2048, 1024) }) == .wrongProportion)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (1280, 960) }) == nil)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (1300, 960) }) == nil, "within 2 %")
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in (1400, 960) }) == .wrongProportion)
    #expect(PSCutout.putBackReason(memory: memory, lastResult: b, imageSize: { _ in nil }) == .patchMissing)
  }

  @Test func putBackStaysAvailableOnTheSameRetouchAfterTheMontage() {
    var memory = PSCutoutMemory(yaw: 0, pitch: 0, fov: 70, width: 1280, height: 960, resultPathAtExtraction: "/r/a.png", patchPath: "/r/retouch.png")
    let montage = URL(fileURLWithPath: "/r/montage.png")
    // The newest result is now the 2:1 montage; the retouch (4:3) is the one that counts.
    let sizes: (URL) -> (Int, Int)? = { $0.lastPathComponent == "retouch.png" ? (1280, 960) : (2048, 1024) }
    #expect(PSCutout.putBackReason(memory: memory, lastResult: montage, imageSize: sizes) == nil)
    #expect(PSCutout.patch(memory: memory, lastResult: montage)?.path == "/r/retouch.png")
    memory.patchPath = nil
    #expect(PSCutout.patch(memory: memory, lastResult: montage)?.path == "/r/montage.png")
  }

  // MARK: Put back — what it does

  @Test func putBackAsStickerPlacesThePatchAtThePoseOfTheExtraction() throws {
    let state = readyState(result: file(256, 128, (10, 120, 200), name: "r.png"))
    _ = try state.extractCutout()
    let retouch = file(1280, 960, (30, 200, 60), name: "retouch.png")
    state.apply(context: context(retouch))
    #expect(state.putBackReason == nil)
    state.mutate { $0.viewMode = .sphere }
    state.putBackAsSticker()
    #expect(state.error == nil && state.doc.stickers.count == 2)
    let placed = state.doc.stickers[1]
    #expect(placed.yaw == 20 && placed.pitch == 0 && placed.hfov == state.doc.lastCutout?.fov && placed.rot == 0)
    #expect(state.doc.selectedID == placed.id && state.doc.viewMode == .plane && state.doc.source == .canvas)
    #expect(FileManager.default.fileExists(atPath: state.projectFolder!.appendingPathComponent(placed.file).path))
    #expect(state.doc.lastCutout?.patchPath == retouch.path)
  }

  @Test func putBackInThePanoramaComposesAndFilesTheMontage() async throws {
    let panorama = file(256, 128, (10, 120, 200), name: "r.png")
    let state = readyState(result: panorama)
    _ = try state.extractCutout()
    state.mutate { $0.camera = PSCamera(yaw: 20, pitch: 0, fov: 70) }
    let retouch = file(1280, 960, (200, 30, 30), name: "retouch.png")
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
    state.apply(context: context(file(1280, 960, (200, 30, 30), name: "retouch.png")))
    await state.putBackInPanorama { _ in ["type": "ok", "problems": ["result: no model"]] }
    #expect(state.error?.contains("no model") == true && state.doc.lastCutout?.patchPath == nil)
  }

  @Test func putBackInThePanoramaNeedsAPanoramaToComposeOn() throws {
    let state = readyState()  // no result when the cutout was taken
    _ = try state.extractCutout()
    state.apply(context: context(file(1280, 960, (200, 30, 30), name: "retouch.png")))
    #expect(state.putBackReason == nil)
    #expect(state.putBackInPanoramaReason == .noPanorama)
  }

  @Test func aNewExtractionResetsThePatch() throws {
    let state = readyState(result: file(256, 128, (10, 120, 200), name: "r.png"))
    _ = try state.extractCutout()
    state.apply(context: context(file(1280, 960, (200, 30, 30), name: "retouch.png")))
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
    #expect(size(of: target)! == (512, 384))
    let empty = PSState(italian: false)
    #expect(throws: PSCutoutError.nothingExtracted) { try empty.saveCutout(to: target) }
  }

  @Test func aMontageDoesNotTouchTheNextProject() async throws {
    let state = readyState(result: file(256, 128, (10, 120, 200), name: "r.png"))
    _ = try state.extractCutout()
    state.apply(context: context(file(1280, 960, (200, 30, 30), name: "retouch.png")))
    // The next project has a cutout of its own: the old project's retouch must not be written into it.
    let other = TestImages.tempFolder()
    var theirs = PanoState()
    theirs.lastCutout = PSCutoutMemory(yaw: 5, pitch: 5, fov: 50, width: 512, height: 384, resultPathAtExtraction: nil, patchPath: nil)
    try theirs.save(to: other)
    await state.putBackInPanorama { _ in
      state.switchProject(folder: other)
      return ["type": "ok"]
    }
    #expect(state.doc.lastCutout?.patchPath == nil)
    #expect(PanoState.load(from: other).lastCutout?.patchPath == nil)
  }

  @Test func theMontageKeepsTheSizeOfALargeResult() async throws {
    let big = file(4200, 2100, (10, 120, 200), name: "big.png")
    let state = readyState(result: big)
    _ = try state.extractCutout()
    state.apply(context: context(file(1280, 960, (200, 30, 30), name: "retouch.png")))
    nonisolated(unsafe) var path = ""
    await state.putBackInPanorama { body in
      path = ((body["result"] as? [String: Any])?["path"] as? String) ?? ""
      return ["type": "ok"]
    }
    let size = try #require(PSCutout.pixelSize(of: URL(fileURLWithPath: path)))
    #expect(size.width == 4200 && size.height == 2100)
  }

  @Test func aPanoramaDeletedAfterTheExtractionIsSaidSo() throws {
    let panorama = file(256, 128, (10, 120, 200), name: "r.png")
    let state = readyState(result: panorama)
    _ = try state.extractCutout()
    state.apply(context: context(file(1280, 960, (200, 30, 30), name: "retouch.png")))
    #expect(state.putBackInPanoramaReason == nil)
    try FileManager.default.removeItem(at: panorama)
    #expect(state.putBackInPanoramaReason == .panoramaMissing)
    #expect(state.putBackReason == nil, "the sticker button does not need the panorama")
  }
}
