import Foundation
import Testing

@testable import LLMChat

@Suite("Action block")
struct ActionBlockTests {
  func block(_ json: String, label: String = "dthub") -> String { "```\(label)\n\(json)\n```" }

  // MARK: Finding

  @Test func aDthubBlockIsFoundInAnyCase() {
    #expect(ActionBlock.find(in: "text\n" + block(#"{"strength":0.5}"#)) == #"{"strength":0.5}"# + "\n")
    #expect(ActionBlock.find(in: block(#"{"strength":0.5}"#, label: "DTHub")) != nil)
  }

  @Test func theLastDthubBlockWins() {
    let reply = block(#"{"strength":0.1}"#) + "\nthen\n" + block(#"{"strength":0.9}"#)
    #expect(ActionBlock.find(in: reply)?.contains("0.9") == true)
  }

  @Test func aJsonBlockThatLooksLikeActionsIsATolerance() {
    #expect(ActionBlock.find(in: block(#"{"fields":{"steps":4}}"#, label: "json")) != nil)
    #expect(ActionBlock.find(in: block(#"{"foo":1}"#, label: "json")) == nil)
    #expect(ActionBlock.find(in: "no blocks here") == nil)
    // A dthub block beats a json one.
    let both = block(#"{"fields":{"steps":4}}"#, label: "json") + "\n" + block(#"{"strength":0.2}"#)
    #expect(ActionBlock.find(in: both)?.contains("0.2") == true)
  }

  @Test func stripTakesTheBlockAndTheExtraSpace() {
    let reply = "Done, I made it darker.\n\n" + block(#"{"strength":0.5}"#) + "\n"
    #expect(ActionBlock.strip(reply) == "Done, I made it darker.")
    #expect(ActionBlock.strip("  plain  ") == "plain")
  }

  // MARK: The body

  func body(_ json: String, italian: Bool = false) -> [String: Any]? { try? ActionBlock.body(from: json, italian: italian).get() }

  @Test func unknownFieldKeysAreDropped() throws {
    let result = try #require(body(#"{"fields":{"prompt":"a cat","steps":4,"foo":1}}"#))
    let fields = try #require(result["fields"] as? [String: Any])
    #expect(Set(fields.keys) == ["prompt", "steps"])
  }

  @Test func loraWithoutAFileIsDroppedAndTheWeightIsKept() throws {
    let result = try #require(body(#"{"loras":[{"file":"x.ckpt","weight":0.6},{"weight":1},{"file":"y.ckpt"}]}"#))
    let loras = try #require(result["loras"] as? [[String: Any]])
    #expect(loras.count == 2 && loras[0]["file"] as? String == "x.ckpt" && loras[0]["weight"] as? Double == 0.6)
    #expect(loras[1]["weight"] == nil)
  }

  @Test func theStrengthIsKept() throws {
    let result = try #require(body(#"{"strength":0.45}"#))
    #expect(result["strength"] as? Double == 0.45)
    #expect(body(#"{"strength":"high"}"#) == nil)
  }

  @Test func aPipelineLosesTheSizeAndGetsTitlesAndAName() throws {
    let json = #"""
      {"pipeline":{"steps":[{"title":"A","fields":{"prompt":"a","width":512}},{"fields":{"steps":4,"height":9}},{"title":"  ","loras":[{"file":"x.ckpt","weight":0.5}],"useOutputAsStart":true}]}}
      """#
    let result = try #require(body(json, italian: true))
    let pipeline = try #require(result["pipeline"] as? [String: Any])
    #expect(pipeline["name"] as? String == "LLM Chat")
    let steps = try #require(pipeline["steps"] as? [[String: Any]])
    #expect(steps.count == 3)
    #expect(steps[0]["title"] as? String == "A" && steps[1]["title"] as? String == "Passaggio 2")
    #expect(steps[2]["title"] as? String == "Passaggio 3" && steps[2]["useOutputAsStart"] as? Bool == true)
    #expect((steps[0]["fields"] as? [String: Any])?.keys.contains("width") == false)
    #expect((steps[1]["fields"] as? [String: Any])?.keys.contains("height") == false)
    #expect((steps[1]["fields"] as? [String: Any])?["steps"] as? Int == 4)
    #expect(steps.allSatisfy { $0["preset"] == nil })
  }

  @Test func aBareListOfStepsIsReadAsThePipeline() throws {
    let result = try #require(body(#"{"pipeline":[{"title":"A","fields":{"prompt":"a"}},{"fields":{"prompt":"b"}}]}"#, italian: false))
    let pipeline = try #require(result["pipeline"] as? [String: Any])
    let steps = try #require(pipeline["steps"] as? [[String: Any]])
    #expect(steps.count == 2 && steps[1]["title"] as? String == "Pass 2")
    #expect(pipeline["name"] as? String == "LLM Chat")
    let many = Array(repeating: #"{"fields":{"steps":4}}"#, count: 21).joined(separator: ",")
    #expect(ActionBlock.body(from: #"{"pipeline":[\#(many)]}"#, italian: false).failureValue == .tooManySteps(21))
  }

  @Test func englishTitlesForEmptyOnes() throws {
    let result = try #require(body(#"{"pipeline":{"steps":[{"fields":{"steps":4}}]}}"#, italian: false))
    let steps = try #require((result["pipeline"] as? [String: Any])?["steps"] as? [[String: Any]])
    #expect(steps[0]["title"] as? String == "Pass 1")
  }

  @Test func moreThan20StepsSendNothingNotEvenTheFieldsOfTheSameBlock() {
    let steps = Array(repeating: #"{"fields":{"steps":4}}"#, count: 21).joined(separator: ",")
    let json = #"{"fields":{"prompt":"x"},"pipeline":{"steps":[\#(steps)]}}"#
    #expect(ActionBlock.body(from: json, italian: false).failureValue == .tooManySteps(21))
    let ok = Array(repeating: #"{"fields":{"steps":4}}"#, count: 20).joined(separator: ",")
    #expect(body(#"{"pipeline":{"steps":[\#(ok)]}}"#) != nil)
  }

  @Test func anEmptyBodyOrOnlyUnknownKeysIsEmpty() {
    #expect(ActionBlock.body(from: "{}", italian: false).failureValue == .empty)
    #expect(ActionBlock.body(from: #"{"foo":1,"fields":{"bar":2}}"#, italian: false).failureValue == .empty)
  }

  @Test func textThatIsNotJSONIsInvalid() {
    if case .invalidJSON? = ActionBlock.body(from: "not json", italian: false).failureValue {} else { Issue.record("expected invalidJSON") }
    if case .invalidJSON? = ActionBlock.body(from: "[1,2]", italian: false).failureValue {} else { Issue.record("expected invalidJSON") }
  }

  // MARK: What to show

  @Test func thePromptsOfABlockAreReadableLines() {
    let single = block(#"{"fields":{"prompt":"a cat","negativePrompt":"blur","steps":4}}"#)
    #expect(ActionBlock.readableLines(in: single, italian: false) == ["Prompt: a cat", "Negative: blur"])
    #expect(ActionBlock.readableLines(in: single, italian: true) == ["Prompt: a cat", "Negativo: blur"])
  }

  @Test func eachPassOfAPipelineShowsItsPromptAndSettingsAreNotShown() {
    let json = #"{"pipeline":{"steps":[{"title":"Noir","fields":{"prompt":"a noir cat"}},{"fields":{"prompt":"a bright cat"}},{"fields":{"steps":20}}]}}"#
    #expect(ActionBlock.readableLines(in: block(json), italian: false) == ["1. Noir: a noir cat", "2. a bright cat"])
    let bare = #"{"pipeline":[{"fields":{"prompt":"x"}}]}"#
    #expect(ActionBlock.readableLines(in: block(bare), italian: false) == ["1. x"])
  }

  @Test func aTextTheAnswerAlreadySaysIsNotRepeated() {
    let reply = "Here: a noir cat, and more.\n" + block(#"{"pipeline":{"steps":[{"fields":{"prompt":"a noir cat"}},{"fields":{"prompt":"a bright cat"}}]}}"#)
    #expect(ActionBlock.readableLines(in: reply, italian: false) == ["2. a bright cat"])
  }

  @Test func deterministicActionsOrNoBlockGiveNothingToRead() {
    #expect(ActionBlock.readableLines(in: block(#"{"fields":{"steps":10},"strength":0.5}"#)).isEmpty)
    #expect(ActionBlock.readableLines(in: "just words").isEmpty)
    #expect(ActionBlock.readableLines(in: block("not json")).isEmpty)
  }

  // MARK: The summary

  @Test func theSummaryListsWhatWasSent() throws {
    let steps = Array(repeating: ["title": "t"], count: 5)
    let sent: [String: Any] = [
      "fields": ["prompt": "x", "steps": 4], "loras": [["file": "a"], ["file": "b"]], "strength": 0.5,
      "pipeline": ["name": "LLM Chat", "steps": steps],
    ]
    let it = ActionBlock.summary(of: sent, answer: ["type": "ok"], italian: true)
    #expect(it.text == "Inviati: prompt, passi, LoRA (2), forza, pipeline (5 passaggi)." && !it.isError)
    let en = ActionBlock.summary(of: sent, answer: ["type": "ok"], italian: false)
    #expect(en.text == "Sent: prompt, steps, LoRAs (2), strength, pipeline (5 passes).")
  }

  @Test func conflictsAreAddedAndAnErrorOfTheAppIsAnError() {
    let sent: [String: Any] = ["fields": ["prompt": "x"]]
    #expect(ActionBlock.summary(of: sent, answer: ["conflicts": 1], italian: false).text.hasSuffix("1 conflict(s) waiting in the app."))
    let error = ActionBlock.summary(of: sent, answer: ["type": "error", "text": "boom"], italian: false)
    #expect(error.text == "boom" && error.isError)
    #expect(ActionBlock.summary(of: sent, answer: nil, italian: false).isError)
  }

  @Test func problemsOfTheAppAreListedAsAnError() {
    let result = ActionBlock.summary(
      of: ["strength": 0.5], answer: ["problems": ["strength: there is no start image."]], italian: false)
    #expect(result.isError && result.text.contains("strength: there is no start image."))
  }
}

extension Result {
  fileprivate var failureValue: Failure? { if case .failure(let error) = self { error } else { nil } }
}
