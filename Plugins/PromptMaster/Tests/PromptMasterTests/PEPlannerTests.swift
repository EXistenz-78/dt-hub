import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

@Suite("Choosing the prompt enhancer")
struct PEPlannerTests {
  /// The kit has no public initializer for the models of the context: they are read from JSON, as the app sends them.
  private func model(_ name: String, vision: Bool = true) -> DTHubLanguageModel {
    let json = #"{"name": "\#(name)", "path": "/models/\#(name)", "supportsImages": \#(vision)}"#
    return try! JSONDecoder().decode(DTHubLanguageModel.self, from: Data(json.utf8))
  }

  private let t2i = "mlx/Qwen-Image-2.1-PE-T2I-MLX-4bit"
  private let i2i = "mlx/Qwen-Image-2.1-PE-I2I-MLX-4bit"

  /// Every enhancer folder has its system prompt file, unless the test says otherwise.
  private func plan(
    family: String? = "qwen_image_2.1", start: String? = nil, moodboard: [String] = [],
    models: [DTHubLanguageModel], sizes: [String: Int64] = [:], files: [String: String]? = nil
  ) -> PEPlan {
    let defaults = ["system_prompt.txt": "T2I SYSTEM", "system_prompt_edit.txt": "EDIT SYSTEM"]
    return PEPlanner.plan(
      family: family, startImage: start, moodboard: moodboard, languageModels: models,
      folderSize: { sizes[$0] ?? 0 },
      readFile: { url in (files ?? defaults)[url.lastPathComponent] })
  }

  private func enhancer(_ plan: PEPlan) -> Enhancer? {
    if case .enhancer(let value) = plan { return value }
    return nil
  }

  @Test func otherFamiliesNeverUseAnEnhancerAndSayNothingAboutIt() {
    #expect(plan(family: "flux2_9b", models: [model(t2i)]) == .generic(reason: nil))
    #expect(plan(family: nil, models: [model(t2i)]) == .generic(reason: nil))
  }

  @Test func withoutAStartImageItIsT2IWithQwensSettings() throws {
    let chosen = try #require(enhancer(plan(models: [model(t2i), model(i2i)])))
    #expect(chosen.kind == .t2i && chosen.model == t2i && chosen.system == "T2I SYSTEM" && chosen.images.isEmpty)
    #expect(chosen.options.temperature == 1 && chosen.options.topK == 20 && chosen.options.presencePenalty == 1.5)
    #expect(chosen.options.maxTokens == 16256 && chosen.options.thinking == true)
  }

  @Test func aMoodboardAloneDoesNotMakeItI2IAndSendsNoPictures() throws {
    let chosen = try #require(enhancer(plan(moodboard: ["/m1.png", "/m2.png"], models: [model(t2i), model(i2i)])))
    #expect(chosen.kind == .t2i && chosen.images.isEmpty)
  }

  @Test func aStartImageMakesItI2IWithTheStartImageFirstThenTheMoodboard() throws {
    let chosen = try #require(enhancer(plan(start: "/s.png", moodboard: ["/m1.png", "/m2.png"], models: [model(t2i), model(i2i)])))
    #expect(chosen.kind == .i2i && chosen.model == i2i && chosen.system == "EDIT SYSTEM")
    #expect(chosen.images == ["/s.png", "/m1.png", "/m2.png"])
    #expect(chosen.options.presencePenalty == 0 && chosen.options.maxTokens == 24000)
  }

  @Test func atMostTenPicturesGoAndTheStartImageIsNeverTheOneCut() throws {
    let moodboard = (1...12).map { "/m\($0).png" }
    let chosen = try #require(enhancer(plan(start: "/s.png", moodboard: moodboard, models: [model(i2i)])))
    #expect(chosen.images.count == 10 && chosen.images.first == "/s.png" && chosen.images.last == "/m9.png")
  }

  @Test func namesWithDashesDotsOrUnderscoresAndAnySuffixAreRecognised() {
    for name in ["qwen3.5_9b_qwen_image_2.1_pe_t2i", "Qwen-Image-2.1-PE-T2I-MLX-4bit", "x/Qwen-Image-2_1-PE-T2I-8bit"] {
      #expect(enhancer(plan(models: [model(name)])) != nil, "\(name)")
    }
    #expect(enhancer(plan(models: [model("Qwen-Image-2.1-PE-I2I-MLX-4bit")])) == nil)  // I2I is not T2I
  }

  @Test func ofTwoFoldersTheBiggestWins() throws {
    let small = model("a/Qwen-Image-2.1-PE-T2I-MLX-4bit"), big = model("a/Qwen-Image-2.1-PE-T2I-MLX-8bit")
    let sizes = [small.path: Int64(5_000), big.path: Int64(9_000)]
    #expect(try #require(enhancer(plan(models: [small, big], sizes: sizes))).model == big.name)
    #expect(try #require(enhancer(plan(models: [big, small], sizes: sizes))).model == big.name)
  }

  @Test func theI2IEnhancerMustReadImages() {
    #expect(plan(start: "/s.png", models: [model(i2i, vision: false)]) == .generic(reason: .modelMissing(.i2i)))
  }

  @Test func withoutTheModelTheGenericOneIsUsedAndTheReasonSaysWhich() {
    #expect(plan(models: []) == .generic(reason: .modelMissing(.t2i)))
    #expect(plan(start: "/s.png", models: [model(t2i)]) == .generic(reason: .modelMissing(.i2i)))
  }

  @Test func withoutTheSystemPromptFileTheGenericOneIsUsedAndTheReasonNamesTheModel() {
    #expect(plan(models: [model(t2i)], files: [:]) == .generic(reason: .systemPromptMissing(model: t2i)))
    #expect(plan(models: [model(t2i)], files: ["system_prompt.txt": "  \n "]) == .generic(reason: .systemPromptMissing(model: t2i)))
  }

  @Test func theOtherSystemPromptFileNamesAreAccepted() throws {
    let t2iFile = try #require(enhancer(plan(models: [model(t2i)], files: ["system_prompt_t2i.txt": "T"])))
    #expect(t2iFile.system == "T")
    let edit = try #require(enhancer(plan(start: "/s.png", models: [model(i2i)], files: ["system_prompt_i2i.txt": "E"])))
    #expect(edit.system == "E")
  }

  @Test func theFolderSizeAddsTheFilesOfTheFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pm-size-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 100).write(to: folder.appendingPathComponent("a.safetensors"))
    try Data(count: 50).write(to: folder.appendingPathComponent("config.json"))
    #expect(PEPlanner.folderSize(folder.path) == 150)
    #expect(PEPlanner.folderSize("/nowhere/\(UUID().uuidString)") == 0)
  }
}
