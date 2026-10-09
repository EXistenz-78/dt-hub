import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

struct ResultInfoTests {
  let en = Locale(identifier: "en_US")
  let it = Locale(identifier: "it_IT")
  let utc = TimeZone(identifier: "UTC")!
  let date = Date(timeIntervalSince1970: 1_790_000_000)

  func result(
    _ job: GenerationJob, fileURL: URL? = nil, saveError: String? = nil, elapsed: TimeInterval? = nil,
    isRestored: Bool = false
  ) -> GeneratedImage {
    GeneratedImage(
      image: testImage(), job: job, date: date, fileURL: fileURL, saveError: saveError, elapsed: elapsed,
      isRestored: isRestored)
  }

  func info(_ image: GeneratedImage, _ locale: Locale? = nil) -> ResultInfo {
    ResultInfo(image, locale: locale ?? en, timeZone: utc)
  }

  func rows(_ info: ResultInfo, _ kind: ResultInfo.Kind) -> [ResultInfo.Row] {
    info.sections.first { $0.kind == kind }?.rows ?? []
  }

  func value(_ info: ResultInfo, _ field: ResultInfo.Field) -> String? {
    info.sections.flatMap(\.rows).first { $0.field == field }?.value
  }

  func job(
    prompt: String = "a cat", negative: String = "", params: GenerationParameters = GenerationParameters(),
    strength: Double? = nil, moodboard: Int = 0, mask: MaskSettings? = nil
  ) -> GenerationJob {
    GenerationJob(
      prompt: prompt, negativePrompt: negative, model: "flux.ckpt", parameters: params,
      imageStrength: strength, moodboardCount: moodboard, maskSettings: mask)
  }

  @Test func minimalJobShowsOnlyThePromptAndTheModelSections() {
    let i = info(result(job()))
    #expect(i.sections.map(\.kind) == [.prompt, .model, .file])
    #expect(rows(i, .prompt).map(\.field) == [.prompt])
    #expect(rows(i, .file).map(\.field) == [.date])
    #expect(i.sections.flatMap(\.rows).allSatisfy { !$0.value.isEmpty })
  }

  @Test func fullJobHasEverySectionInOrder() {
    var p = GenerationParameters(loras: [LoRASelection(file: "a.ckpt"), LoRASelection(file: "b.ckpt", weight: 0.5)])
    p.advanced.clipSkip = 2
    p.extra = ["foo": .int(3)]
    let url = URL(fileURLWithPath: "/tmp/out/x.png")
    let i = info(
      result(
        job(negative: "ugly", params: p, strength: 0.65, moodboard: 2, mask: MaskSettings()), fileURL: url,
        elapsed: 42))
    #expect(i.sections.map(\.kind) == [.prompt, .model, .loras, .input, .advanced, .extra, .file])
  }

  @Test func negativePromptRowOnlyWhenNotEmpty() {
    #expect(value(info(result(job())), .negativePrompt) == nil)
    #expect(value(info(result(job(negative: "ugly"))), .negativePrompt) == "ugly")
  }

  @Test func sentPromptOnlyWhenTriggersChangeThePrompt() {
    let withTrigger = GenerationParameters(loras: [LoRASelection(file: "x.ckpt", trigger: "zzz")])
    #expect(value(info(result(job(params: withTrigger))), .sentPrompt) == "zzz a cat")
    #expect(value(info(result(job())), .sentPrompt) == nil)
  }

  @Test func sizeAndSeedAreFormattedPlainly() {
    let p = GenerationParameters(width: 1024, height: 1024, seed: 4_294_967_295)
    let i = info(result(job(params: p)), it)
    #expect(value(i, .size) == "1024 × 1024")
    #expect(value(i, .seed) == "4294967295")
  }

  @Test func shiftIsAutoWhenResolutionDependent() {
    let auto = GenerationParameters(shift: 3.5, resolutionDependentShift: true)
    let fixed = GenerationParameters(shift: 3.5, resolutionDependentShift: false)
    #expect(value(info(result(job(params: auto))), .shift) == "auto")
    #expect(value(info(result(job(params: fixed))), .shift) == "3.5")
    #expect(value(info(result(job(params: fixed)), it), .shift) == "3,5")
  }

  @Test func cfgZeroRowOnlyWhenOn() {
    #expect(value(info(result(job())), .cfgZero) == nil)
    let on = GenerationParameters(cfgZeroStar: true, cfgZeroInitSteps: 2)
    #expect(value(info(result(job(params: on))), .cfgZero) == "2")
  }

  @Test func loraRowsCarryFileWeightModeAndTrigger() {
    let p = GenerationParameters(loras: [
      LoRASelection(file: "x.ckpt", weight: 0.8), LoRASelection(file: "y.ckpt", weight: 1, trigger: "zzz"),
    ])
    #expect(rows(info(result(job(params: p))), .loras).map(\.value) == ["x.ckpt · 0.8 · all", "y.ckpt · 1 · all · zzz"])
  }

  @Test func inputRows() {
    let i = info(result(job(strength: 0.6543, moodboard: 3)))
    #expect(value(i, .imageStrength) == "0.65")
    #expect(value(i, .moodboard) == "3")
  }

  @Test func maskRow() {
    let on = info(result(job(mask: MaskSettings(blur: 1.5, outset: 0, preserveOriginal: true))))
    #expect(value(on, .mask) == "blur 1.5 · outset 0 · preserve")
    let off = info(result(job(mask: MaskSettings(blur: 1.5, outset: 0, preserveOriginal: false))))
    #expect(value(off, .mask) == "blur 1.5 · outset 0")
  }

  @Test func advancedListsOnlyValuesThatDiffer() {
    #expect(rows(info(result(job())), .advanced).isEmpty)
    var p = GenerationParameters()
    p.advanced.hiresFix = true
    p.advanced.clipSkip = 2
    let r = rows(info(result(job(params: p))), .advanced)
    #expect(r.map(\.field) == [.advanced(key: "clipSkip"), .advanced(key: "hiresFix")])
    #expect(r.map(\.value) == ["2", "true"])
  }

  @Test func extraRowsPerEntry() {
    var p = GenerationParameters()
    p.extra = ["b": .string("x"), "a": .int(3)]
    let r = rows(info(result(job(params: p))), .extra)
    #expect(r.map(\.field) == [.extra(key: "a"), .extra(key: "b")])
    #expect(r.map(\.value) == ["3", "\"x\""])
  }

  @Test func timeRow() {
    #expect(value(info(result(job())), .time) == nil)
    #expect(value(info(result(job(), elapsed: 41.6)), .time) == "42sec")
  }

  @Test func unsavedImageShowsTheErrorAndNoFile() {
    let i = info(result(job(), fileURL: nil, saveError: "disk full"))
    #expect(value(i, .notSaved) == "disk full")
    #expect(value(i, .fileName) == nil)
    #expect(value(i, .folder) == nil)
  }

  @Test func savedImageShowsNameAndFolder() {
    let i = info(result(job(), fileURL: URL(fileURLWithPath: "/tmp/out/x.png")))
    #expect(value(i, .fileName) == "x.png")
    #expect(value(i, .folder) == "/tmp/out")
  }

  @Test func restoredImageGivesTheSameRows() {
    #expect(info(result(job(), isRestored: true)) == info(result(job())))
  }

  @Test func dateRowFollowsTheLocale() {
    #expect(value(info(result(job()), en), .date) != value(info(result(job()), it), .date))
  }
}
