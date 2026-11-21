import CoreGraphics
import Foundation
import Testing

@testable import TiledUpscale

/// The tile in the Moodboard (MiniMax H3 Image and the like): no start image, no mask, and the plug-in keeps the strips shared
/// with the neighbours as they were.
struct TUMoodboardTests {
  let folder = TestImages.temporaryFolder()
  let preset = TUPresetTable.preset(forFamily: "flux2_9b")!

  private func session(moodboard: Bool) -> TUSession {
    TUSession(
      source: TestImages.solid(1280, 1024, (10, 20, 30)), factor: 1, overlap: .standard,
      settings: TUSettings(free: 256, blur: 30, outset: 30, fade: 0), loraWeight: 1, trigger: "", preset: preset, tempFolder: folder,
      tileInMoodboard: moodboard)
  }

  private func object(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

  private func previous(_ name: String, _ width: Int, _ height: Int, _ rgb: (UInt8, UInt8, UInt8)) -> TUNextRequest.Previous {
    TUNextRequest.Previous(
      path: TestImages.write(TestImages.solid(width, height, rgb), in: folder, name: name).path, width: width, height: height)
  }

  @Test func theTileGoesToTheMoodboardWithNoStartImageNoMaskAndNoStrength() throws {
    let s = session(moodboard: true)
    _ = s.next(TUNextRequest(index: 1, count: 2, previous: nil))
    let answer = object(s.next(TUNextRequest(index: 2, count: 2, previous: previous("m1.png", 1024, 1024, (200, 0, 0)))))
    let board = try #require(answer["moodboard"] as? [[String: Any]])
    #expect(board.count == 1)
    let path = try #require(board.first?["path"] as? String)
    #expect(TUImage.load(URL(fileURLWithPath: path)) != nil)
    #expect(answer["startImage"] == nil && answer["mask"] == nil && answer["maskSettings"] == nil && answer["strength"] == nil)
    #expect((answer["size"] as? [String: Int])?["width"] == 512)
  }

  @Test func theCanvasStaysTheDefault() {
    let s = session(moodboard: false)
    let answer = object(s.next(TUNextRequest(index: 1, count: 2, previous: nil)))
    #expect(answer["startImage"] != nil && answer["moodboard"] == nil && answer["strength"] != nil)
  }

  @Test func onlyTheMaskedPartOfAMoodboardResultIsKept() throws {
    let s = session(moodboard: true)
    _ = s.next(TUNextRequest(index: 1, count: 2, previous: nil))
    _ = s.next(TUNextRequest(index: 2, count: 2, previous: previous("n1.png", 1024, 1024, (200, 0, 0))))
    // The second tile (x 768…1280) comes back all blue: the strip 768…1024 shared with the first tile must stay red.
    let done = s.end("finished", previous: previous("n2.png", 512, 1024, (0, 0, 200)))
    let image = try #require(done)
    #expect(TestImages.pixel(image, 900, 500)[0] == 200, "the shared strip stays as the first tile made it")
    #expect(TestImages.pixel(image, 1100, 500)[2] == 200, "the new part is the second tile's")
  }

  @Test func theTilesCanBeUpTo4096AndTheAutomaticOneStaysUnder2048() {
    #expect(TUSettings.tileRange == 1024...4096)
    #expect(TUSettings.defaults(for: .standard).clamped(overlap: .standard).tile == TileConstants.tile)
    var big = TUSettings.standard
    big.tile = 9999
    #expect(big.clamped(overlap: .standard).tile == 4096)
    #expect(TUSettings.autoTile(shortestSide: 20000, overlap: .standard) == 2048)
  }

  @MainActor @Test func thePickIsKeptInTheChoice() {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.tileInMoodboard = true
    #expect(s.currentChoice.tileInMoodboard)
    s.applyChoice(TUChoice(factor: 2, overlap: 256, loraWeight: 1))
    #expect(!s.tileInMoodboard)
  }
}
