import CoreGraphics
import Foundation
import Testing

@testable import TiledUpscale

@MainActor
struct TUStateRegenerationTests {
  let folder = TestImages.temporaryFolder()

  /// A state that ran a whole enlargement of a 512 px picture (one tile of 1024) the way the app does.
  private func finishedState(photoSize: Int = 512, factor: Int = 2) async throws -> (TUState, sent: [[String: Any]]) {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.family = "flux2_9b"
    s.tempFolder = folder.path
    s.setImage(TestImages.solid(photoSize, photoSize, (10, 20, 30)), name: "a")
    s.factor = factor
    var sent: [[String: Any]] = []
    s.contribute = { sent.append($0); return ["type": "ok"] }
    await s.prepare(confirmed: true, contribute: { _ in ["type": "ok"] }, registerPreset: { _ in nil })
    let plan = try #require(s.plan)
    var previous = ""
    for index in 1...plan.count {
      let message = previous.isEmpty
        ? #"{"type":"session.next","index":\#(index),"count":\#(plan.count)}"#
        : #"{"type":"session.next","index":\#(index),"count":\#(plan.count),"previous":\#(previous)}"#
      let reply = try #require(JSONSerialization.jsonObject(with: await s.sessionNext(Data(message.utf8))) as? [String: Any])
      let size = try #require(reply["size"] as? [String: Int])
      let url = TestImages.write(TestImages.solid(size["width"]!, size["height"]!, (200, 0, 0)), in: folder, name: "r\(index).png")
      previous = #"{"path":"\#(url.path)","width":\#(size["width"]!),"height":\#(size["height"]!)}"#
    }
    let last = try #require(JSONSerialization.jsonObject(with: Data(previous.utf8)) as? [String: Any])
    await s.sessionEnded(
      reason: "finished",
      previous: TUNextRequest.Previous(
        path: last["path"] as! String, width: last["width"] as! Int, height: last["height"] as! Int))
    return (s, sent)
  }

  @Test func theFinishedPictureCanBeMadeAgainAndTheLastTileIsInThePreview() async throws {
    let (s, _) = try await finishedState(photoSize: 1000)
    #expect(s.canRegenerate)
    #expect(s.tilesDone == s.plan?.count)
    #expect(s.resultReady)
  }

  @Test func clickingTheTilePicksItAndAgainLetsItGo() async throws {
    let (s, _) = try await finishedState(photoSize: 1000)
    s.selectTile(atX: 0.01, y: 0.01)
    #expect(s.selectedTile == 0 && s.selectedTileName == "1A")
    s.selectTile(atX: 0.99, y: 0.99)
    #expect(s.selectedTileName == "3C")
    s.selectTile(atX: 0.99, y: 0.99)
    #expect(s.selectedTile == nil)
  }

  @Test func regeneratingProposesAOnePassPipelineWithTheTilesOwnInstructions() async throws {
    let (s, _) = try await finishedState(photoSize: 1000)
    s.extraPrompt = "general"
    s.selectTile(atX: 0.01, y: 0.01)
    s.tileExtra = "only here"
    var pipeline: [String: Any] = [:]
    await s.prepareRegeneration(contribute: { pipeline = ($0["pipeline"] as? [String: Any]) ?? [:]; return ["type": "ok"] }, registerPreset: { _ in nil })
    #expect(pipeline["passes"] as? Int == 1 && pipeline["guided"] as? Bool == true)
    #expect(s.isPrepared && s.regeneratingTile == 0)
    let reply = try #require(
      JSONSerialization.jsonObject(with: await s.sessionNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))) as? [String: Any])
    #expect((reply["fields"] as? [String: Any])?["prompt"] as? String == TUPresetTable.fluxPrompt + " general only here")
    // The tile's own text can still change before the pass is asked for.
    s.tileExtra = ""
    await s.sessionEnded(reason: "stopped")
    #expect(s.canRegenerate, "a stopped tile leaves the picture whole")
    #expect(s.regeneratingTile == nil)
  }

  @Test func changingTheExtraInstructionsDoesNotStopThePreparedSession() async throws {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.family = "flux2_9b"
    s.tempFolder = folder.path
    s.setImage(TestImages.solid(512, 512, (1, 2, 3)), name: "a")
    await s.prepare(confirmed: true, contribute: { _ in ["type": "ok"] }, registerPreset: { _ in nil })
    #expect(s.isPrepared)
    s.extraPrompt = "warm light"
    #expect(s.isPrepared, "the text is read when the tile is asked for")
    let reply = try #require(
      JSONSerialization.jsonObject(with: await s.sessionNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))) as? [String: Any])
    #expect((reply["fields"] as? [String: Any])?["prompt"] as? String == TUPresetTable.fluxPrompt + " warm light")
  }

  @Test func changingTheSettingsOrThePictureDropsTheFinishedPicture() async throws {
    let (s, _) = try await finishedState(photoSize: 1000)
    s.tileSize = 1536
    #expect(!s.canRegenerate && s.selectedTile == nil)
    let (t, _) = try await finishedState(photoSize: 1000)
    t.setImage(TestImages.solid(600, 600, (1, 1, 1)), name: "b")
    #expect(!t.canRegenerate)
  }

  @Test func theExtraInstructionsAreKeptPerProject() {
    let one = folder.appendingPathComponent("one")
    let two = folder.appendingPathComponent("two")
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.switchProject(folder: one)
    s.extraPrompt = "sharper"
    s.switchProject(folder: two)
    #expect(s.extraPrompt == "")
    s.switchProject(folder: one)
    #expect(s.extraPrompt == "sharper")
  }
}
