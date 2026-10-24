import Foundation
import HubKit
import Testing

@testable import HubCore

/// Un prompt che porta già una tabella di riquadri (come lo manda Prompt Master F3 con «Invia»): il PUP lo tratta col suo `*_bbox`.
struct PupBoxesTests {
  static let layoutPrompt = """
    A woman <woman_1> beside a lantern <lantern_1>.

    [
      {
        "id": "woman_1",
        "bbox": [245, 245, 925, 650],
        "desc": "a woman"
      },
      {
        "id": "lantern_1",
        "bbox": [389, 807, 991, 956],
        "desc": "a stone lantern"
      }
    ]
    """
  static let editPrompt = """
    Modify <ref_image_0> by adding <el_1> from <ref_image_1>.

    [
      {
        "id": "el_1",
        "from": "ref_image_1",
        "src_bbox": [78, 92, 974, 950],
        "tgt_bbox": [488, 67, 952, 379],
        "desc": "a ninja"
      }
    ]
    """
  let pup = LanguageModelProfile.Pup(t2i: "T2I", i2i: "I2I", t2iBbox: "T2I BBOX", i2iBbox: "I2I BBOX")

  @Test func aPromptEndingWithATableOfBoxesIsDetected() throws {
    let found = try #require(PupBoxes.detect(Self.layoutPrompt))
    #expect(found.prompt == "A woman <woman_1> beside a lantern <lantern_1>.")
    #expect(found.rows.map(\.id) == ["woman_1", "lantern_1"] && found.rows[1].bbox == [389, 807, 991, 956])
    let edit = try #require(PupBoxes.detect(Self.editPrompt))
    #expect(edit.rows[0].from == "ref_image_1" && edit.rows[0].src == [78, 92, 974, 950] && edit.rows[0].tgt == [488, 67, 952, 379])
  }

  @Test func otherTrailingListsAreNotTables() {
    #expect(PupBoxes.detect(#"A sign "[SALE]""#) == nil)
    #expect(PupBoxes.detect("A cat. [1, 2, 3, 4]") == nil)
    #expect(PupBoxes.detect(#"A cat. [{"id": "cat_1", "bbox": [0.1, 0.1, 0.5, 0.5], "desc": "x"}]"#) == nil)  // 0–1 coordinates are not the 0–1000 canvas
    #expect(PupBoxes.detect(#"A cat. [{"id": "not valid", "bbox": [10, 10, 500, 500], "desc": "x"}]"#) == nil)
  }

  @Test func enhanceWithATableAndNoPicturesUsesT2iBboxWithTheLockedRows() throws {
    let request = PromptBrief.enhance(PromptPair(prompt: Self.layoutPrompt, negative: ""), pup: pup, images: EnhanceImages())
    #expect(request.options.system == "T2I BBOX" && request.options.presencePenalty == 1.5 && request.images.isEmpty)
    #expect(request.prompt.hasPrefix("ORIGINAL PROMPT:\nA woman <woman_1> beside a lantern <lantern_1>.\n\nLOCKED BOUNDING-BOX ANNOTATIONS ("))
    #expect(request.prompt.hasSuffix(#"[{"id": "woman_1", "bbox": [245, 245, 925, 650], "desc": "a woman"}, {"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "a stone lantern"}]"#))
    #expect(request.locked?.count == 2)
  }

  @Test func enhanceWithATableAndPicturesUsesI2iBboxWithTheEditScaffold() throws {
    let start = URL(fileURLWithPath: "/s.png"), ref = URL(fileURLWithPath: "/r.png")
    let request = PromptBrief.enhance(
      PromptPair(prompt: Self.editPrompt, negative: ""), pup: pup, images: EnhanceImages(start: start, references: [ref]))
    #expect(request.options.system == "I2I BBOX" && request.options.presencePenalty == 0 && request.images == [start, ref])
    #expect(request.prompt.hasPrefix("Reference images follow in attachment order: ref_image_0, ref_image_1, ...\nUser editing instruction: ORIGINAL PROMPT:\nModify <ref_image_0>"))
    #expect(request.prompt.hasSuffix("\nDecide the edit, imagine the target image, and output the annotation record."))
    #expect(request.prompt.contains(#"{"id": "el_1", "from": "ref_image_1", "src_bbox": [78, 92, 974, 950], "tgt_bbox": [488, 67, 952, 379], "desc": "a ninja"}"#))
  }

  @Test func aPupWithoutTheBboxPromptsOrAPromptWithoutATableGoesTheUsualWay() {
    let plain = LanguageModelProfile.Pup(t2i: "T2I", i2i: "I2I")
    let withTable = PromptBrief.enhance(PromptPair(prompt: Self.layoutPrompt, negative: ""), pup: plain, images: EnhanceImages())
    #expect(withTable.options.system == "T2I" && withTable.prompt == Self.layoutPrompt && withTable.locked == nil)
    let noTable = PromptBrief.enhance(PromptPair(prompt: "a cat", negative: ""), pup: pup, images: EnhanceImages())
    #expect(noTable.options.system == "T2I" && noTable.locked == nil)
  }

  @Test func reconcileKeepsOurRowsRenamesAndAddsValidOnes() throws {
    let locked = try #require(PupBoxes.detect(Self.layoutPrompt)).rows
    let answer = #"A woman <person_1> with a lantern <lantern_1>, a cat <cat_1>. [{"id": "person_1", "bbox": [245, 245, 925, 650], "desc": "An adult woman."}, {"id": "lantern_1", "bbox": [1, 1, 2, 2], "desc": "A mossy lantern."}, {"id": "cat_1", "bbox": [700, 420, 990, 560], "desc": "A black cat."}]"#
    let text = try #require(PupBoxes.reconcile(answer, locked: locked))
    #expect(text.hasPrefix("A woman <woman_1> with a lantern <lantern_1>, a cat <cat_1>. [{"))
    #expect(text.contains(#"{"id": "woman_1", "bbox": [245, 245, 925, 650], "desc": "An adult woman."}"#))
    #expect(text.contains(#"{"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "A mossy lantern."}"#))  // our box, the model's desc
    #expect(text.hasSuffix(#"{"id": "cat_1", "bbox": [700, 420, 990, 560], "desc": "A black cat."}]"#))  // added, cited and valid
    #expect(PupBoxes.reconcile("No table at all.", locked: locked) == nil)
  }
}

@MainActor
struct PupAssistantTests {
  let recorder = PromptRecorder()
  let model = LanguageModelDescriptor(path: "/m/pup", name: "pup", sizeBytes: 1, supportsImages: true)
  let pup = LanguageModelProfile.Pup(t2i: "T2I", i2i: "I2I", t2iBbox: "T2I BBOX", i2iBbox: "I2I BBOX")
  let a = URL(fileURLWithPath: "/tmp/a.png")

  func assistant() -> PromptAssistant {
    let recorder = recorder, model = model, pup = pup
    return PromptAssistant(
      resolve: { _, _, _ in .success(.init(model: model, profile: LanguageModelProfile(pup: pup))) },
      respond: { prompt, images, options, _ throws(LanguageModelError) in try await recorder.respond(prompt, images, options) })
  }

  @Test func theOptionsAndPicturesOfEveryPupRequest() async {
    recorder.result = .success("A caption.")
    let current = PromptPair(prompt: "a cat", negative: "")
    _ = await assistant().enhance(current, family: "flux3_5b")
    _ = await assistant().enhance(current, family: "flux3_5b", images: EnhanceImages(start: a))
    _ = await assistant().describe(imageAt: a, current: current, family: "flux3_5b")
    #expect(recorder.calls.map(\.options.system) == ["T2I", "I2I", "I2I"])
    #expect(recorder.calls.map(\.options.presencePenalty) == [1.5, 0, 0])
    #expect(recorder.calls.map(\.images) == [[], [a], [a]])
  }

  @Test func atMostTenPicturesGoToThePup() {
    let refs = (1...12).map { URL(fileURLWithPath: "/tmp/r\($0).png") }
    let request = PromptBrief.enhance(PromptPair(prompt: "x", negative: ""), pup: pup, images: EnhanceImages(start: a, references: refs))
    #expect(request.images.count == 10 && request.images.first == a)
  }

  @Test func aTablePromptComesBackReconciledAndWithoutATableItFails() async {
    let prompt = PromptPair(prompt: PupBoxesTests.layoutPrompt, negative: "")
    recorder.result = .success(#"A woman <woman_1> and <lantern_1>. [{"id": "woman_1", "bbox": [245, 245, 925, 650], "desc": "An adult woman."}, {"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "A lantern."}]"#)
    let result = await assistant().enhance(prompt, family: "flux3_5b")
    #expect(result?.prompt == #"A woman <woman_1> and <lantern_1>. [{"id": "woman_1", "bbox": [245, 245, 925, 650], "desc": "An adult woman."}, {"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "A lantern."}]"#)
    recorder.result = .success("Only a caption, no table.")
    let failed = assistant()
    let none = await failed.enhance(prompt, family: "flux3_5b")
    #expect(none == nil && failed.failure == .emptyAnswer)
  }

  @Test func theProfileReadsTheBboxPromptsToo() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pup-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #"{"t2i":"A","i2i":"B","t2i_bbox":"C","i2i_bbox":"D"}"#.write(to: dir.appendingPathComponent("system_prompts.json"), atomically: true, encoding: .utf8)
    #expect(LanguageModelProfile.load(folder: dir).pup == .init(t2i: "A", i2i: "B", t2iBbox: "C", i2iBbox: "D"))
  }
}
