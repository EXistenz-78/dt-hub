import Foundation
import HubKit
import Testing

@testable import HubCore

/// A prompt-expansion model that ships its own request (MiniMax-H3-Image-PE): `prompt/t2i/` and `prompt/edit/`.
@MainActor
struct PromptExpanderTests {
  func folder(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LMExpander-\(UUID())")
    for (name, text) in files {
      let file = dir.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try text.write(to: file, atomically: true, encoding: .utf8)
    }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  let expander = LanguageModelProfile.Expander(
    t2iSystem: "SYS", t2iTask: "Rules {{\"a\":\"b\"}}\ninput_text: {}\noutput_text:\n", editTask: "EDIT RULES")
  let current = PromptPair(prompt: "a cat on a roof", negative: "ugly")
  let a = URL(fileURLWithPath: "/a.png"), b = URL(fileURLWithPath: "/b.png")

  // MARK: The folder

  @Test func theFolderOfTheModelGivesItsPromptsAndItsRequestValues() throws {
    let params = #"{"temperature":0.9,"top_p":0.8,"top_k":30,"max_tokens":2048,"presence_penalty":0.0}"#
    let p = LanguageModelProfile.load(
      folder: try folder([
        "prompt/t2i/system_prompt.txt": "SYS\n", "prompt/t2i/task_prompt.txt": "T {}\nout:\n",
        "prompt/t2i/request_params.json": params, "prompt/edit/task_prompt.txt": "EDIT\n",
      ]))
    #expect(
      p.expander
        == LanguageModelProfile.Expander(
          t2iSystem: "SYS", t2iTask: "T {}\nout:\n", editTask: "EDIT\n", temperature: 0.9, topP: 0.8, topK: 30,
          maxTokens: 2048))
  }

  @Test func withoutRequestValuesTheReleasedOnesApplyAndTheEditPromptMayBeMissing() throws {
    let p = LanguageModelProfile.load(
      folder: try folder(["prompt/t2i/system_prompt.txt": "SYS", "prompt/t2i/task_prompt.txt": "T {}"]))
    #expect(p.expander == LanguageModelProfile.Expander(t2iSystem: "SYS", t2iTask: "T {}", editTask: nil))
    #expect(p.expander?.temperature == 1.0 && p.expander?.topP == 0.95 && p.expander?.topK == 20 && p.expander?.maxTokens == 4096)
  }

  @Test func aFolderWithoutBothTextToImageFilesIsNotAnExpander() throws {
    #expect(LanguageModelProfile.load(folder: try folder(["prompt/t2i/system_prompt.txt": "SYS"])).expander == nil)
    #expect(LanguageModelProfile.load(folder: try folder(["prompt/t2i/task_prompt.txt": "T {}"])).expander == nil)
    // A template with no place for the request is no template.
    #expect(
      LanguageModelProfile.load(
        folder: try folder(["prompt/t2i/system_prompt.txt": "SYS", "prompt/t2i/task_prompt.txt": "no slot"])
      ).expander == nil)
    #expect(LanguageModelProfile.load(folder: try folder([:])).expander == nil)
  }

  // MARK: The requests

  @Test func theTemplateIsFilledAsPythonFormatDoes() {
    #expect(PromptBrief.pythonFormat("a {{\"k\":1}} b {} c", "X") == "a {\"k\":1} b X c")
    // The request goes in as it is, braces included, and only the first slot takes it.
    #expect(PromptBrief.pythonFormat("{} and {}", "{x}") == "{x} and ")
  }

  @Test func enhanceWithoutPicturesSendsTheSystemPromptAndTheFilledTemplate() {
    let request = PromptBrief.enhance(current, expander: expander, images: EnhanceImages(), ratio: { _ in nil })
    #expect(request.prompt == "Rules {\"a\":\"b\"}\ninput_text: a cat on a roof\noutput_text:\n")
    #expect(request.images.isEmpty)
    #expect(
      request.options
        == LanguageModelOptions(system: "SYS", temperature: 1.0, topP: 0.95, topK: 20, maxTokens: 4096, thinking: true))
  }

  @Test func enhanceWithPicturesSendsTheEditPromptFirstWithNoSystemPrompt() {
    let request = PromptBrief.enhance(
      PromptPair(prompt: "swap the \"bag\"", negative: ""), expander: expander,
      images: EnhanceImages(start: a, references: [b]), ratio: { $0.path == "/a.png" ? "3:2" : nil })
    let expected =
      "EDIT RULES\n\nReference Image Count:\n2 input image(s), labeled <Picture 1> through <Picture 2>.\n\n"
      + "Reference Media:\n- <Picture 1> [aspect_ratio 3:2]\n\nReference Media:\n- <Picture 2> [aspect_ratio unavailable]\n\n"
      + "\nUser Editing Instruction (JSON string):\n\"swap the \\\"bag\\\"\"\n\nUser Aspect Ratio Selection:\nadaptive\n\n"
      + "Apply the instructions above to the supplied inputs and reference images. Output only the required two-field JSON object."
    #expect(request.prompt == expected)
    #expect(request.images == [a, b])
    #expect(
      request.options
        == LanguageModelOptions(system: nil, temperature: 1.0, topP: 0.95, topK: 20, maxTokens: 4096, thinking: true))
  }

  @Test func picturesWithoutAnEditPromptFallBackToTextToImage() {
    var textOnly = expander
    textOnly.editTask = nil
    let request = PromptBrief.enhance(current, expander: textOnly, images: EnhanceImages(start: a), ratio: { _ in nil })
    #expect(request.images.isEmpty && request.options.system == "SYS")
  }

  @Test func generateSendsThePictureWithTheTextToImageRequest() {
    let request = PromptBrief.describe(imageAt: a, current: current, expander: expander)
    #expect(request.prompt == "Rules {\"a\":\"b\"}\ninput_text: \(PromptBrief.expanderDescribeRequest)\noutput_text:\n")
    #expect(request.images == [a] && request.options.system == "SYS" && request.options.thinking == true)
    let focused = PromptBrief.describe(imageAt: a, current: current, expander: expander, focus: .style)
    #expect(focused.prompt.contains("input_text: \(PromptBrief.expanderDescribeRequest) Use the picture for ONLY the style"))
    #expect(focused.prompt.contains("User's text:\na cat on a roof"))
  }

  @Test func theRatioOfAPictureIsReducedToItsLowestTerms() {
    #expect(PromptBrief.reducedRatio(width: 3000, height: 2000) == "3:2")
    #expect(PromptBrief.reducedRatio(width: 2048, height: 2048) == "1:1")
    #expect(PromptBrief.reducedRatio(width: 0, height: 10) == nil)
  }

  // MARK: The answer

  @Test func theExpandedCaptionIsThePrompt() {
    let raw = "thinking…</think>\n{\"expanded_caption\": \"A \\\"cat\\\".\", \"aspect_ratio\": \"3:2\"}"
    #expect(PromptBrief.parse(raw) == PromptPair(prompt: "A \"cat\".", negative: ""))
    #expect(
      PromptBrief.parse(#"{"expanded_caption":"<Subject 1> stays.","target_aspect_ratio":"1:1"}"#)?.prompt
        == "<Subject 1> stays.")
  }

  // MARK: The assistant

  final class Log {
    var calls: [(String, [URL], LanguageModelOptions)] = []
  }

  func assistant(_ log: Log) -> PromptAssistant {
    let profile = LanguageModelProfile(expander: expander)
    let model = LanguageModelDescriptor(path: "/m/pe", name: "pe", sizeBytes: 1, supportsImages: true)
    return PromptAssistant(
      resolve: { _, _, _ in .success(.init(model: model, profile: profile)) },
      respond: { prompt, images, options, _ throws(LanguageModelError) in
        log.calls.append((prompt, images, options))
        return #"{"expanded_caption":"A cat.","aspect_ratio":"1:1"}"#
      }, imageRatio: { _ in "1:1" })
  }

  @Test func enhanceIsTextToImageWithAnEmptyControlAndEditingWithPictures() async {
    let log = Log()
    let plain = await assistant(log).enhance(current, family: "minimax_h3_image")
    #expect(plain?.prompt == "A cat.")
    #expect(log.calls.last?.0 == PromptBrief.enhance(current, expander: expander, images: EnhanceImages(), ratio: { _ in nil }).prompt)
    #expect(log.calls.last?.2.system == "SYS")
    let images = EnhanceImages(start: a)
    _ = await assistant(log).enhance(current, family: "minimax_h3_image", images: images)
    #expect(log.calls.last?.0 == PromptBrief.enhance(current, expander: expander, images: images, ratio: { _ in "1:1" }).prompt)
    #expect(log.calls.last?.1 == [a] && log.calls.last?.2.system == nil)
  }

  @Test func generateUsesTheExpanderToo() async {
    let log = Log()
    let result = await assistant(log).describe(imageAt: a, current: current, family: "minimax_h3_image")
    #expect(result?.prompt == "A cat.")
    #expect(log.calls.last?.0 == PromptBrief.describe(imageAt: a, current: current, expander: expander).prompt)
    #expect(log.calls.last?.1 == [a])
  }
}
