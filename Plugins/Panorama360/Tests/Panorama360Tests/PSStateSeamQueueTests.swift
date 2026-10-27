import CoreGraphics
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Seam in the queue")
struct PSStateSeamQueueTests {
  func picture(_ rgb: (UInt8, UInt8, UInt8), name: String = "r.png") -> URL {
    TestImages.file(TestImages.solid(1024, 512, rgb.0, rgb.1, rgb.2), in: TestImages.tempFolder(), name: name, type: "public.png")
  }

  func context(_ url: URL?) -> Data {
    let last = url.map { #","lastResult":{"path":"\#($0.path)","name":"\#($0.lastPathComponent)"}"# } ?? ""
    return Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"\#(last)}"#.utf8)
  }

  func state(result: URL?) -> PSState {
    let state = PSState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    state.apply(context: context(result))
    return state
  }

  let accept: PSContribute = { _ in ["type": "ok"] }

  func prepared(_ rgb: (UInt8, UInt8, UInt8) = (200, 30, 30)) async -> (PSState, URL) {
    let url = picture(rgb)
    let s = state(result: url)
    await s.prepareSeamCorrection(contribute: accept)
    return (s, url)
  }

  func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }

  @Test func captureNeedsAPreparedSeam() async {
    let s = state(result: picture((200, 30, 30)))
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    #expect(s.queueCapture(folder: folder) == nil)
    await s.prepareSeamCorrection(contribute: accept)
    #expect(s.queueCapture(folder: folder) != nil)
  }

  @Test func captureCopiesThePanorama() async throws {
    let (s, original) = await prepared()
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    let captured = try #require(s.queueCapture(folder: folder))
    let name = try #require(captured["panorama"] as? String)
    #expect(name == "panorama.png")
    #expect(try bytes(folder.appendingPathComponent(name)) == bytes(original))
  }

  @Test func captureKeepsThePanoramaTheSessionWasMadeWith() async throws {
    let (s, red) = await prepared((200, 30, 30))
    let blue = picture((30, 30, 200), name: "newer.png")
    s.apply(context: context(blue))  // a newer result arrives after the correction was prepared
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    let captured = try #require(s.queueCapture(folder: folder))
    let copy = folder.appendingPathComponent(try #require(captured["panorama"] as? String))
    #expect(try bytes(copy) == bytes(red))
    #expect(try bytes(copy) != bytes(blue))
  }

  @Test func prepareBuildsTheSameSeamFromTheCopy() async throws {
    let (s1, _) = await prepared()
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: folder))

    let s2 = state(result: nil)
    let problem = await s2.queuePrepare(folder: folder, state: captured, model: nil, contribute: accept)
    #expect(problem == nil)
    #expect(s2.isSeamPrepared)
    let first = try #require(s1.seamSession), second = try #require(s2.seamSession)
    #expect(NSDictionary(dictionary: first.estimate()).isEqual(to: second.estimate()))
    let a = first.next(index: 1, count: 1), b = second.next(index: 1, count: 1)
    func file(_ pass: [String: Any], _ key: String) throws -> Data {
      let box = try #require(pass[key] as? [String: Any])
      return try bytes(URL(fileURLWithPath: try #require(box["path"] as? String)))
    }
    #expect(try file(a, "startImage") == file(b, "startImage"))
    #expect(a["mask"] == nil && b["mask"] == nil)
  }

  @Test func theDescriptionOfThePlaceTravelsWithTheEntry() async throws {
    let url = picture((200, 30, 30))
    let s1 = state(result: url)
    s1.mutate { $0.description = "a quiet lake" }
    await s1.prepareSeamCorrection(contribute: accept)
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: folder))
    #expect(captured["description"] as? String == "a quiet lake")
    s1.mutate { $0.description = "changed afterwards" }  // the tab moves on: the entry keeps what it was queued with
    let s2 = state(result: nil)
    #expect(await s2.queuePrepare(folder: folder, state: captured, model: nil, contribute: accept) == nil)
    let pass = try #require(s2.seamSession).next(index: 1, count: 1)
    #expect((pass["fields"] as? [String: Any])?["prompt"] as? String == "a quiet lake")
  }

  @Test func prepareDoesNotChangeTheShownResult() async throws {
    let (s1, _) = await prepared()
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: folder))
    let shown = picture((30, 200, 30), name: "shown.png")
    let s2 = state(result: shown)
    #expect(await s2.queuePrepare(folder: folder, state: captured, model: nil, contribute: accept) == nil)
    #expect(s2.lastResultPath == shown.path)
  }

  @Test func prepareFailsForAMissingFile() async throws {
    let (s1, _) = await prepared()
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: folder))
    try FileManager.default.removeItem(at: folder.appendingPathComponent("panorama.png"))
    let s2 = state(result: nil)
    #expect(await s2.queuePrepare(folder: folder, state: captured, model: nil, contribute: accept) != nil)
    #expect(!s2.isSeamPrepared)
  }

  @Test func prepareFailsWhenTheAppRefuses() async throws {
    let (s1, _) = await prepared()
    let folder = TestImages.tempFolder().appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: folder))
    let s2 = state(result: nil)
    let problem = await s2.queuePrepare(
      folder: folder, state: captured, model: nil, contribute: { _ in ["type": "error", "text": "boom"] })
    #expect(problem == "boom")
    #expect(!s2.isSeamPrepared)
  }

  @Test func captureIsNilOnceTheRunEnded() async throws {
    let (s, _) = await prepared()
    let end = Data(#"{"type":"session.end","reason":"stopped"}"#.utf8)
    await s.seamEnded(end, contribute: accept)
    #expect(s.queueCapture(folder: TestImages.tempFolder().appendingPathComponent("q")) == nil)
  }
}
