import CoreGraphics
import Foundation
import Testing

@testable import TiledUpscaleLab

struct TUSessionTests {
  let folder = TestImages.temporaryFolder()
  let preset = TUPresetTable.preset(forFamily: "flux2_9b")!

  /// 1280 × 1024, factor 1: two tiles with the standard overlap (0…1024 and 768…1280).
  private func session(overlap: TileOverlap = .standard, weight: Double = 1, trigger: String = "TRIG", settings: TUSettings? = nil) -> TUSession {
    let source = TestImages.solid(1280, 1024, (10, 20, 30))
    return TUSession(
      source: source, factor: 1, overlap: overlap, settings: settings ?? TUSettings(free: overlap.rawValue, blur: 30, outset: 30, fade: 0),
      loraWeight: weight, trigger: trigger, preset: preset, tempFolder: folder)
  }

  private func request(_ index: Int, count: Int = 2, previous: (String, Int, Int)? = nil) -> TUNextRequest {
    TUNextRequest(
      index: index, count: count,
      previous: previous.map { TUNextRequest.Previous(path: $0.0, width: $0.1, height: $0.2) })
  }

  private func object(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  private func size(_ answer: [String: Any]) -> (Int, Int) {
    let box = answer["size"] as? [String: Int] ?? [:]
    return (box["width"] ?? 0, box["height"] ?? 0)
  }

  private func load(_ answer: [String: Any], _ key: String) -> CGImage? {
    guard let path = (answer[key] as? [String: Any])?["path"] as? String else { return nil }
    return TUImage.load(URL(fileURLWithPath: path))
  }

  private func previousFile(_ name: String, _ width: Int, _ height: Int, _ rgb: (UInt8, UInt8, UInt8)) -> (String, Int, Int) {
    (TestImages.write(TestImages.solid(width, height, rgb), in: folder, name: name).path, width, height)
  }

  @Test func theFirstAnswerHasNoMaskAndTheFirstTileSize() throws {
    let s = session()
    #expect(s.plan.count == 2)
    let answer = object(s.next(request(1)))
    #expect(size(answer) == (1024, 1024))
    #expect(answer["mask"] == nil)
    #expect(answer["title"] as? String == "Tile 1A")
    let tile = try #require(load(answer, "startImage"))
    #expect(tile.width == 1024 && tile.height == 1024)
    #expect(TestImages.pixel(tile, 5, 5) == [10, 20, 30, 255])
  }

  @Test func theSecondAnswerMasksFromTheFreeMargin() throws {
    let s = session()
    _ = s.next(request(1))
    let answer = object(s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0)))))
    #expect(size(answer) == (512, 1024))
    let mask = try #require(load(answer, "mask"))
    #expect(mask.width == 512 && mask.height == 1024)
    #expect(TestImages.pixel(mask, 255, 500)[0] == 0)
    #expect(TestImages.pixel(mask, 256, 500)[0] == 255)
    #expect(TestImages.pixel(mask, 511, 1023)[0] == 255)
    let settings = answer["maskSettings"] as? [String: Any]
    #expect(settings?["blur"] as? Double == 30 && settings?["outset"] as? Int == 30)
    #expect(settings?["preserveOriginal"] as? Bool == true)
    #expect(answer["title"] as? String == "Tile 1B")
  }

  @Test func theTileCutOutIncludesThePastedNeighbourInTheOverlap() throws {
    let s = session()
    _ = s.next(request(1))
    let answer = object(s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0)))))
    let tile = try #require(load(answer, "startImage"))
    #expect(TestImages.pixel(tile, 10, 10) == [200, 0, 0, 255], "the first 256 columns are the neighbour's result")
    #expect(TestImages.pixel(tile, 255, 10) == [200, 0, 0, 255])
    #expect(TestImages.pixel(tile, 256, 10) == [10, 20, 30, 255], "beyond the overlap it is still the enlarged source")
  }

  @Test func doneAfterTheLastTileAndTheComposedImageIsReturned() throws {
    let s = session()
    _ = s.next(request(1))
    _ = s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0))))
    let done = object(s.next(request(3, count: 2, previous: previousFile("p2.png", 512, 1024, (0, 0, 200)))))
    #expect(done["done"] as? Bool == true)
    let composed = try #require(s.end("finished"))
    #expect(composed.width == 1280 && composed.height == 1024)
    #expect(TestImages.pixel(composed, 100, 100) == [200, 0, 0, 255])
    #expect(TestImages.pixel(composed, 1100, 100) == [0, 0, 200, 255])
  }

  @Test func endWithAnotherReasonReturnsNil() {
    let s = session()
    _ = s.next(request(1))
    #expect(s.end("stopped") == nil)
  }

  @Test func theWideOverlapStartsAt704AndMasksFrom320() throws {
    let s = session(overlap: .wide)
    _ = s.next(request(1))
    let answer = object(s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0)))))
    #expect(size(answer) == (576, 1024))
    let mask = try #require(load(answer, "mask"))
    #expect(TestImages.pixel(mask, 319, 5)[0] == 0)
    #expect(TestImages.pixel(mask, 320, 5)[0] == 255)
    let tile = try #require(load(answer, "startImage"))
    #expect(TestImages.pixel(tile, 319, 5) == [200, 0, 0, 255])
    #expect(TestImages.pixel(tile, 320, 5) == [10, 20, 30, 255])
  }

  @Test func promptAndLoRAWeightAreInTheAnswer() {
    let s = session(weight: 0.8, trigger: "TRIG")
    let answer = object(s.next(request(1)))
    let fields = answer["fields"] as? [String: Any]
    #expect(fields?["prompt"] as? String == TUPrompt.text(trigger: "TRIG"))
    #expect(fields?["steps"] as? Int == 4)
    let lora = (answer["loras"] as? [[String: Any]])?.first
    #expect(lora?["file"] as? String == "f2_ultra_real_v5_pro_lora_f16.ckpt")
    #expect(lora?["weight"] as? Double == 0.8)
    #expect(answer["preset"] as? String == "TUP · FLUX.2 klein 9B")
    #expect(answer["strength"] as? Double == 1)
  }

  @Test func aResultOfTheWrongSizeEndsTheSessionWithAProblem() {
    let s = session()
    _ = s.next(request(1))
    let answer = object(s.next(request(2, previous: previousFile("bad.png", 100, 100, (1, 1, 1)))))
    #expect(answer["done"] as? Bool == true)
    #expect(s.problem != nil)
    #expect(s.end("finished") == nil)
  }

  @Test func theRequestIsReadFromTheAppsJSON() throws {
    let json = Data(#"{"type":"session.next","index":3,"count":12,"previous":{"path":"/t/p.png","width":1024,"height":512}}"#.utf8)
    let read = try #require(TUMessages.parseNext(json))
    #expect(read.index == 3 && read.count == 12)
    #expect(read.previous?.path == "/t/p.png" && read.previous?.width == 1024)
    #expect(TUMessages.parseNext(Data(#"{"type":"context"}"#.utf8)) == nil)
  }

  @Test func thePreviewFillsAsTilesComeBack() throws {
    let s = session()
    let empty = try #require(s.previewImage())
    #expect(empty.width == 1200 && empty.height == 960, "the picture's ratio, 1200 px on the long side")
    #expect(TestImages.pixel(empty, 10, 10)[3] == 0, "nothing is shown before a tile is back")
    #expect(s.completedTiles == 0)
    _ = s.next(request(1))
    _ = s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0))))
    let first = try #require(s.previewImage())
    #expect(s.completedTiles == 1)
    #expect(TestImages.pixel(first, 100, 100) == [200, 0, 0, 255], "tile 1A is on, at full opacity")
    #expect(TestImages.pixel(first, 1100, 100)[3] == 0, "tile 1B is not back yet")
    _ = s.next(request(3, previous: previousFile("p2.png", 512, 1024, (0, 0, 200))))
    let both = try #require(s.previewImage())
    #expect(s.completedTiles == 2)
    #expect(TestImages.pixel(both, 1100, 100) == [0, 0, 200, 255])
    // The overlap (768…1024 → 720…960 in the preview) belongs to the later tile, as in the real picture.
    #expect(TestImages.pixel(both, 800, 100) == [0, 0, 200, 255])
    #expect(TestImages.pixel(both, 100, 100) == [200, 0, 0, 255])
  }

  @Test func theInputFadesFromTheNeighbourResultToTheSourceAtTheEndOfTheOverlap() throws {
    let s = session(settings: TUSettings(free: 200, blur: 30, outset: 30, fade: 48))
    _ = s.next(request(1))
    let answer = object(s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0)))))
    let tile = try #require(load(answer, "startImage"))
    #expect(TestImages.pixel(tile, 100, 500) == [200, 0, 0, 255], "deep in the neighbour's part it is the neighbour's result")
    let edge = TestImages.pixel(tile, 255, 500)
    #expect(abs(Int(edge[0]) - 10) < 4 && abs(Int(edge[1]) - 20) < 4, "at the end of the overlap it is the source: no step")
    let middle = TestImages.pixel(tile, 232, 500)
    #expect(abs(Int(middle[0]) - 105) < 12, "half way it is half and half")
    #expect(TestImages.pixel(tile, 300, 500) == [10, 20, 30, 255], "beyond the overlap it is the source")
  }

  @Test func withNoFadeTheEdgeStaysHard() throws {
    let s = session(settings: TUSettings(free: 200, blur: 30, outset: 30, fade: 0))
    _ = s.next(request(1))
    let answer = object(s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0)))))
    let tile = try #require(load(answer, "startImage"))
    #expect(TestImages.pixel(tile, 255, 500) == [200, 0, 0, 255])
    #expect(TestImages.pixel(tile, 256, 500) == [10, 20, 30, 255])
  }

  @Test func theMaskSettingsAndTheFreeMarginFollowTheSliders() throws {
    let s = session(settings: TUSettings(free: 120, blur: 12, outset: 7, fade: 0))
    _ = s.next(request(1))
    let answer = object(s.next(request(2, previous: previousFile("p1.png", 1024, 1024, (200, 0, 0)))))
    let settings = answer["maskSettings"] as? [String: Any]
    #expect(settings?["blur"] as? Double == 12 && settings?["outset"] as? Int == 7)
    let mask = try #require(load(answer, "mask"))
    #expect(TestImages.pixel(mask, 119, 5)[0] == 0 && TestImages.pixel(mask, 120, 5)[0] == 255)
  }
}
