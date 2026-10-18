import Foundation
import Testing

@testable import HubKit

struct GuidedPipelineContractTests {
  private func contribution(_ json: String) -> PluginContribution? {
    PluginContribution(message: Data(json.utf8))
  }

  private func answer(_ json: String?, tileLimit: Int = 2048) -> SessionAnswer {
    SessionAnswer.parse(json.map { Data($0.utf8) }, tileLimit: tileLimit)
  }

  private let pass = """
    {"title":"Tile 2B","startImage":{"path":"/t/tile.png","name":"tile"},"mask":{"path":"/t/mask.png"},
    "maskSettings":{"blur":30,"outset":30,"preserveOriginal":true},"size":{"width":512,"height":1024},
    "preset":"TUP","fields":{"prompt":"x","steps":4},"loras":[{"file":"a.ckpt","weight":0.8}],"strength":1}
    """

  @Test func readsAGuidedPipelineWithNoSteps() throws {
    let read = try #require(
      contribution(
        #"{"pipeline":{"name":"Tiled Upscale","guided":true,"passes":12,"estimate":{"preset":"TUP"}}}"#))
    let pipeline = try #require(read.pipeline)
    #expect(pipeline.guided?.passes == 12)
    #expect(pipeline.guided?.estimate.preset == "TUP")
    #expect(pipeline.steps.isEmpty)
    #expect(pipeline.passCount == 12)
  }

  @Test func ignoresAGuidedPipelineWithoutPasses() {
    #expect(contribution(#"{"pipeline":{"name":"x","guided":true,"passes":0}}"#)?.pipeline == nil)
    #expect(contribution(#"{"pipeline":{"name":"x","guided":true}}"#)?.pipeline == nil)
  }

  @Test func aStaticPipelineKeepsItsPassCount() throws {
    let read = try #require(
      contribution(#"{"pipeline":{"name":"x","steps":[{"preset":"a"},{"preset":"b"},{"preset":"c"}]}}"#))
    #expect(read.pipeline?.passCount == 3)
    #expect(read.pipeline?.guided == nil)
  }

  @Test func existingPipelineParsingIsUnchanged() throws {
    let read = try #require(contribution(#"{"pipeline":{"name":"x","steps":[{"preset":"a"}]}}"#))
    let step = try #require(read.pipeline?.steps.first)
    #expect(step.mask == nil && step.maskSettings == nil && step.size == nil)
  }

  @Test func readsTheAutonomousPass() throws {
    guard case .pass(let step) = answer(pass) else { Issue.record("not a pass"); return }
    #expect(step.title == "Tile 2B")
    #expect(step.startImage?.path == "/t/tile.png")
    #expect(step.mask?.path == "/t/mask.png")
    #expect(step.maskSettings == MaskSettings(blur: 30, outset: 30, preserveOriginal: true))
    #expect(step.size == PipelineSize(width: 512, height: 1024))
    #expect(step.preset == "TUP")
    #expect(step.fields.values[.prompt] == .text("x"))
    #expect(step.loras.first?.weight == 0.8)
    #expect(step.strength == 1)
  }

  @Test func rejectsABadSizeOrNoImage() {
    #expect(answer(pass.replacingOccurrences(of: "512", with: "500")) == .invalid("size must be a multiple of 64"))
    #expect(
      answer(pass.replacingOccurrences(of: #""height":1024"#, with: #""height":2112"#))
        == .invalid("size is larger than 2048"))
    #expect(answer(#"{"size":{"width":512,"height":512}}"#) == .invalid("the pass has no startImage"))
    #expect(answer(#"{"startImage":{"path":"/t/a.png"}}"#) == .invalid("the pass has no size"))
  }

  @Test func doneAndNoAnswer() {
    #expect(answer(#"{"done":true}"#) == .done)
    #expect(answer(nil) == .invalid("no answer"))
    #expect(answer("not json") == .invalid("no answer"))
  }

  @Test func nextRequestCarriesThePreviousFile() throws {
    let request = SessionNextRequest(
      index: 3, count: 12, previous: SessionPrevious(path: "/t/pass-2.png", width: 1024, height: 1024))
    let json = try #require(JSONSerialization.jsonObject(with: request.data()) as? [String: Any])
    #expect(json["type"] as? String == "session.next")
    #expect(json["index"] as? Int == 3 && json["count"] as? Int == 12)
    #expect((json["previous"] as? [String: Any])?["path"] as? String == "/t/pass-2.png")
    let first = try #require(
      JSONSerialization.jsonObject(with: SessionNextRequest(index: 1, count: 12, previous: nil).data())
        as? [String: Any])
    #expect(first["previous"] == nil)
  }

  @Test func endMessageNamesTheReason() throws {
    let json = try #require(
      JSONSerialization.jsonObject(with: PluginSession.endMessage(.stopped)) as? [String: Any])
    #expect(json["type"] as? String == "session.end")
    #expect(json["reason"] as? String == "stopped")
  }

  @Test func readsAResultWithItsDescription() throws {
    let read = try #require(
      contribution(#"{"result":{"path":"/t/r.png","name":"Tiled Upscale 001","description":"Tiled Upscale 2× · 9 tile"}}"#))
    #expect(read.result == PluginResult(image: PluginImageRef(name: "Tiled Upscale 001", path: "/t/r.png"), description: "Tiled Upscale 2× · 9 tile"))
    #expect(!read.isEmpty)
    let bare = try #require(contribution(#"{"result":{"path":"/t/r.png"}}"#))
    #expect(bare.result?.description == "" && bare.result?.image.name == "r.png")
    #expect(contribution(#"{"result":{"name":"x"}}"#)?.result == nil, "no path, no result")
  }
}
