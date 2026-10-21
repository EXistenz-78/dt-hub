import CoreGraphics
import Foundation
import Testing

@testable import TiledUpscale

/// The way the app really drives a session: it does not ask again after the last pass, so the last result comes with `end`.
@MainActor
struct TUSessionRegenerationTests {
  private let source = TestImages.solid(1300, 700, (10, 20, 30))
  private let settings = TUSettings(free: 200, blur: 30, outset: 30, fade: 0)

  private func session(folder: URL, extra: String = "") throws -> TUSession {
    let preset = try #require(TUPresetTable.preset(forFamily: "flux2_9b"))
    return TUSession(
      source: source, factor: 2, overlap: .standard, settings: settings, loraWeight: 1, trigger: "", extraPrompt: extra,
      preset: preset, tempFolder: folder)
  }

  private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let data = try #require(TUImage.rgba(image))
    let at = (y * image.width + x) * 4
    return Array(data[at..<at + 3])
  }

  private func answer(_ data: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]) }

  private func result(_ color: (UInt8, UInt8, UInt8), size: [String: Int], folder: URL, name: String) throws -> TUNextRequest.Previous {
    let width = try #require(size["width"])
    let height = try #require(size["height"])
    let url = TestImages.write(TestImages.solid(width, height, color), in: folder, name: name)
    return TUNextRequest.Previous(path: url.path, width: width, height: height)
  }

  /// Every declared pass is asked exactly once (as the driver does); the last result goes to `end`.
  private func runLikeTheApp(_ session: TUSession, folder: URL, color: (UInt8, UInt8, UInt8)) throws -> CGImage {
    var previous: TUNextRequest.Previous?
    for index in 1...session.plan.count {
      let reply = try answer(session.next(TUNextRequest(index: index, count: session.plan.count, previous: previous)))
      let size = try #require(reply["size"] as? [String: Int])
      previous = try result(color, size: size, folder: folder, name: "r\(index).png")
    }
    return try #require(session.end("finished", previous: previous))
  }

  @Test func theLastResultReachesThePictureAndThePreview() throws {
    let folder = TestImages.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let s = try session(folder: folder)
    let composed = try runLikeTheApp(s, folder: folder, color: (200, 0, 0))
    #expect(try pixel(composed, composed.width - 1, composed.height - 1) == [200, 0, 0], "the last tile is in the picture")
    #expect(s.completedTiles == s.plan.count)
    let preview = try #require(s.previewImage())
    #expect(try pixel(preview, preview.width - 1, preview.height - 1) == [200, 0, 0], "and in the preview")
  }

  @Test func theLastResultIsNotComposedTwiceWhenTheAppAskedAgain() throws {
    let folder = TestImages.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let s = try session(folder: folder)
    var previous: TUNextRequest.Previous?
    for index in 1...(s.plan.count + 1) {
      let reply = try answer(s.next(TUNextRequest(index: index, count: s.plan.count, previous: previous)))
      if reply["done"] as? Bool == true { break }
      let size = try #require(reply["size"] as? [String: Int])
      previous = try result((200, 0, 0), size: size, folder: folder, name: "r\(index).png")
    }
    _ = s.end("finished", previous: previous)
    #expect(s.completedTiles == s.plan.count)
    #expect(s.problem == nil)
  }

  @Test func theExtraInstructionsFollowThePresetPromptAndCanChangeBetweenTiles() throws {
    let folder = TestImages.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let s = try session(folder: folder, extra: "keep the sky")
    let first = try answer(s.next(TUNextRequest(index: 1, count: s.plan.count, previous: nil)))
    #expect((first["fields"] as? [String: Any])?["prompt"] as? String == TUPresetTable.fluxPrompt + " keep the sky")
    s.extraPrompt = ""
    let size = try #require(first["size"] as? [String: Int])
    let previous = try result((1, 1, 1), size: size, folder: folder, name: "a.png")
    let second = try answer(s.next(TUNextRequest(index: 2, count: s.plan.count, previous: previous)))
    #expect((second["fields"] as? [String: Any])?["prompt"] as? String == TUPresetTable.fluxPrompt)
  }

  @Test func aTileMadeAgainStartsFromTheOriginalAndKeepsTheJoin() throws {
    let folder = TestImages.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let s = try session(folder: folder)
    _ = try runLikeTheApp(s, folder: folder, color: (200, 0, 0))
    #expect(s.isComplete)
    #expect(!s.beginRegeneration(of: 999, loraWeight: 1, extraPrompt: ""))
    #expect(s.beginRegeneration(of: 1, loraWeight: 1, extraPrompt: "more grain"))
    let reply = try answer(s.next(TUNextRequest(index: 1, count: 1, previous: nil)))
    #expect((reply["fields"] as? [String: Any])?["prompt"] as? String == TUPresetTable.fluxPrompt + " more grain")
    let startPath = try #require((reply["startImage"] as? [String: Any])?["path"] as? String)
    let start = try #require(TUImage.load(URL(fileURLWithPath: startPath)))
    #expect(try pixel(start, 10, 100) == [200, 0, 0], "the strip shared with the tile on the left is what that tile made")
    #expect(try pixel(start, 600, 100) == [10, 20, 30], "the rest is the original, not the old result")
    let size = try #require(reply["size"] as? [String: Int])
    let blue = try result((0, 0, 200), size: size, folder: folder, name: "again.png")
    let composed = try #require(s.end("finished", previous: blue))
    let tile = s.plan.tiles[1]
    #expect(try pixel(composed, tile.rect.x + 600, 100) == [0, 0, 200])
    #expect(try pixel(composed, 100, 100) == [200, 0, 0], "the other tiles stay as they were")
    #expect(s.isComplete)
    #expect(s.completedTiles == s.plan.count)
  }

  @Test func aTileMadeAgainThatIsStoppedLeavesThePictureAsItWas() throws {
    let folder = TestImages.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let s = try session(folder: folder)
    _ = try runLikeTheApp(s, folder: folder, color: (200, 0, 0))
    #expect(s.beginRegeneration(of: 0, loraWeight: 1, extraPrompt: ""))
    _ = s.next(TUNextRequest(index: 1, count: 1, previous: nil))
    #expect(s.end("stopped") == nil)
    #expect(s.isComplete)
    #expect(s.beginRegeneration(of: 2, loraWeight: 1, extraPrompt: ""), "another tile can still be made")
  }

  @Test func aRunThatDidNotFinishDropsThePicture() throws {
    let folder = TestImages.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let s = try session(folder: folder)
    _ = s.next(TUNextRequest(index: 1, count: s.plan.count, previous: nil))
    #expect(s.end("stopped") == nil)
    #expect(!s.isComplete)
    #expect(!s.beginRegeneration(of: 0, loraWeight: 1, extraPrompt: ""))
  }
}
