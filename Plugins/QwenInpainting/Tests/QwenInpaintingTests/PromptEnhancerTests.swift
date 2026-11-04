import DTHubPluginKit
import Foundation
import Testing

@testable import QwenInpainting

@Suite("Prompt enhancer")
struct PromptEnhancerTests {
  func model(_ name: String, family: String?, use: String?, vision: Bool, path: String = "/nowhere") throws -> DTHubLanguageModel {
    var json = #"{"name":"\#(name)","path":"\#(path)","supportsImages":\#(vision)"#
    if let family { json += #","family":"\#(family)""# }
    if let use { json += #","use":"\#(use)""# }
    return try JSONDecoder().decode(DTHubLanguageModel.self, from: Data((json + "}").utf8))
  }

  @Test func onlyAQwen21I2IModelWithVisionCountAndTheFirstByNameWins() throws {
    let models = [
      try model("b-pe", family: "qwen_image_2.1", use: "i2i", vision: true),
      try model("a-pe", family: "qwen_image_2.1", use: "i2i", vision: true),
      try model("c", family: "qwen_image_2.1", use: "t2i", vision: true),
      try model("d", family: "*", use: "i2i", vision: true),
      try model("e", family: "qwen_image_2.1", use: "i2i", vision: false),
    ]
    #expect(PromptEnhancer.model(in: models)?.name == "a-pe")
    #expect(PromptEnhancer.model(in: Array(models[2...])) == nil)
    #expect(PromptEnhancer.model(in: []) == nil)
  }

  func folder(_ files: [String: String]) throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qi-pe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    return dir.path
  }

  @Test func theSystemPromptComesFromTheI2IFileThenTheGenericOneThenTheBuiltInText() throws {
    let both = try model("m", family: "qwen_image_2.1", use: "i2i", vision: true, path: folder(["system_prompt_i2i.txt": " I2I ", "system_prompt.txt": "G"]))
    #expect(PromptEnhancer.systemPrompt(for: both) == "I2I")
    let generic = try model("m", family: "qwen_image_2.1", use: "i2i", vision: true, path: folder(["system_prompt.txt": "G"]))
    #expect(PromptEnhancer.systemPrompt(for: generic) == "G")
    let none = try model("m", family: "qwen_image_2.1", use: "i2i", vision: true, path: folder([:]))
    #expect(PromptEnhancer.systemPrompt(for: none) == PromptEnhancer.builtInSystem)
  }

  @Test func theRequestAddsTheKeepLine() {
    #expect(PromptEnhancer.request(composed: "X") == "X\n\nKeep every reference to the colored marks and the instruction to remove them.")
  }

  @Test func theAnswerIsCleaned() {
    #expect(PromptEnhancer.cleaned("  \"Inside the red box: a cat.\"  ") == "Inside the red box: a cat.")
    #expect(PromptEnhancer.cleaned("   ") == nil)
    #expect(PromptEnhancer.cleaned("plain") == "plain")
    #expect(PromptEnhancer.cleaned("\"\"") == nil)
  }

  // Qwen's PE system prompt asks for a JSON object and for reasoning first: only the rewritten prompt may reach the tab.
  @Test func theJSONAnswerGivesOnlyTheRewrittenPrompt() {
    let json = #"{"rewritten_prompt": "Remove the hat inside the red circle.", "wh_ratio": "", "ratio_follow": "<image1>"}"#
    #expect(PromptEnhancer.cleaned(json) == "Remove the hat inside the red circle.")
    #expect(PromptEnhancer.cleaned("```json\n\(json)\n```") == "Remove the hat inside the red circle.")
  }

  @Test func theReasoningNeverReachesThePrompt() {
    let json = #"{"rewritten_prompt": "Remove the hat."}"#
    #expect(PromptEnhancer.cleaned("<think>Let me carefully analyze the image…</think>\n\n\(json)") == "Remove the hat.")
    #expect(PromptEnhancer.cleaned("<think>Let me carefully analyze the image… and then") == nil)
    #expect(PromptEnhancer.cleaned("<think>x</think>") == nil)
  }

  @Test func theEnhancerGetsRoomToThinkAndTheDecodingOfPromptMaster() {
    #expect(PromptEnhancer.options.thinking == true)
    #expect((PromptEnhancer.options.maxTokens ?? 0) >= 16256)
  }
}
