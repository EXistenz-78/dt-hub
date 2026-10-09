import Foundation
import Testing

@testable import BatchPlus

@MainActor
@Suite("Batch plus state")
struct BatchPlusStateTests {
  func state() -> BatchPlusState {
    let defaults = UserDefaults(suiteName: "bp-state-\(UUID().uuidString)")!
    return BatchPlusState(store: BatchPlusStore(defaults: defaults))
  }

  let withParameters = Data(
    #"""
    {"type":"context","tempFolder":"/t","model":"m.ckpt","parameters":{"width":832,"height":1216,"steps":8,"guidanceScale":1.5,"seed":99,"resolutionDependentShift":false,"shift":3,"loras":[{"file":"x.ckpt","weight":0.4,"mode":0,"trigger":""}]}}
    """#.utf8)
  let withoutParameters = Data(#"{"type":"context","tempFolder":"/t","model":"m.ckpt"}"#.utf8)

  @Test func theContextGivesTheBaseValues() throws {
    let s = state()
    s.apply(context: withParameters)
    let base = try #require(s.base)
    #expect(base.steps == 8 && base.guidanceScale == 1.5 && base.seed == 99 && base.shift == 3)
    #expect(base.loras == [BatchBase.LoRA(file: "x.ckpt", weight: 0.4)])
    #expect(s.modelName == "m.ckpt")
  }

  @Test func withoutParametersTheParametersModeIsOffWithTheMessageAndPromptsStillWork() {
    let s = state()
    #expect(s.blocker(italian: false) == L.text(.noParameters, italian: false))
    s.apply(context: withoutParameters)
    #expect(s.base == nil)
    #expect(s.blocker(italian: false) == L.text(.needsNewApp, italian: false))
    #expect(s.pipeline(italian: false) == nil)
    s.session.mode = .prompts
    s.session.promptText = "- a\n- b"
    #expect(s.blocker(italian: false) == nil)
    #expect(s.pipeline(italian: false)?["name"] as? String == "Batch plus · Prompts")
  }

  @Test func theSendButtonNeedsAnIncrementAndValidBoxes() {
    let s = state()
    s.apply(context: withParameters)
    #expect(s.blocker(italian: false) == L.text(.noIncrements, italian: false))
    s.session.increments["steps"] = "1.5"
    #expect(s.blocker(italian: false) == L.text(.invalidIncrement, italian: false))
    s.session.increments["steps"] = "2"
    #expect(s.blocker(italian: false) == nil)
    let steps = s.pipeline(italian: false)?["steps"] as? [[String: Any]]
    #expect(steps?.count == 3)
  }

  @Test func promptsNeedAtLeastTwoItems() {
    let s = state()
    s.session.mode = .prompts
    s.session.promptText = "- only one"
    #expect(s.blocker(italian: false) == L.text(.promptsFew, italian: false))
  }

  @Test func aProjectSwitchLoadsItsStateAndDoesNotWriteBack() throws {
    let s = state()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bp-sw-\(UUID().uuidString)")
    var saved = BatchPlusSession.initial()
    saved.count = 9
    var store = BatchPlusStore(defaults: UserDefaults(suiteName: "bp-x-\(UUID().uuidString)")!)
    store.folder = dir
    store.save(saved)
    s.switchProject(folder: dir, adoptLegacy: false)
    #expect(s.session.count == 9)
    s.session.count = 12
    #expect(store.load()?.count == 12)
  }

  @Test func theAnswerOfTheAppBecomesTheStatusLine() {
    #expect(BatchPlusState.describe(nil, italian: false) == L.text(.notAnswered, italian: false))
    #expect(BatchPlusState.describe(["type": "ok"], italian: false) == "Sent.")
    #expect(BatchPlusState.describe(["conflicts": 2], italian: false) == "Sent. 2 conflict(s) waiting in the app.")
    #expect(BatchPlusState.describe(["type": "error", "text": "boom"], italian: false) == "boom")
  }

  @Test func aSamplerAloneIsAReasonToSend() {
    let s = state()
    s.apply(context: withParameters)
    #expect(s.blocker(italian: false) == L.text(.noIncrements, italian: false))
    s.session.samplers = [5]
    #expect(s.blocker(italian: false) == nil)
  }

  @Test func reducingThePassesTrimsTheSamplers() {
    let s = state()
    s.session.count = 5
    s.session.samplers = [1, 2, 3, 4, 5]
    s.session.count = 3
    #expect(s.session.samplers == [1, 2, 3])
  }
}
