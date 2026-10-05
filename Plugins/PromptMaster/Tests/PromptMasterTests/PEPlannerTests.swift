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
    family: String? = "qwen_image_2.1", models: [DTHubLanguageModel], sizes: [String: Int64] = [:],
    files: [String: String]? = nil
  ) -> PEPlan {
    PEPlanner.plan(
      family: family, languageModels: models, folderSize: { sizes[$0] ?? 0 },
      readFile: { url in (files ?? ["system_prompt.txt": "T2I SYSTEM"])[url.lastPathComponent] })
  }

  private func enhancer(_ plan: PEPlan) -> Enhancer? {
    if case .enhancer(let value) = plan { return value }
    return nil
  }

  @Test func otherFamiliesNeverUseAnEnhancerAndSayNothingAboutIt() {
    #expect(plan(family: "flux2_9b", models: [model(t2i)]) == .generic(reason: nil))
    #expect(plan(family: nil, models: [model(t2i)]) == .generic(reason: nil))
  }

  @Test func qwenImage21UsesTheTextToImageEnhancerWithQwensSettings() throws {
    let chosen = try #require(enhancer(plan(models: [model(t2i)])))
    #expect(chosen.model == t2i && chosen.system == "T2I SYSTEM")
    #expect(chosen.options.temperature == 1 && chosen.options.topP == 0.95 && chosen.options.topK == 20)
    #expect(chosen.options.presencePenalty == 1.5 && chosen.options.maxTokens == 16256 && chosen.options.thinking == true)
    #expect(chosen.options.timeout == 900)
  }

  @Test func theImageEditingEnhancerIsNeverUsedWhateverIsInTheFolder() {
    // It belongs to a plug-in of its own: with only the I2I enhancer there is no enhancer here.
    #expect(plan(models: [model(i2i)]) == .generic(reason: .modelMissing))
    let both = enhancer(plan(models: [model(i2i), model(t2i)]))
    #expect(both?.model == t2i)
  }

  @Test func namesWithDashesDotsOrUnderscoresAndAnySuffixAreRecognised() {
    for name in ["qwen3.5_9b_qwen_image_2.1_pe_t2i", "Qwen-Image-2.1-PE-T2I-MLX-4bit", "x/Qwen-Image-2_1-PE-T2I-8bit"] {
      #expect(enhancer(plan(models: [model(name)])) != nil, "\(name)")
    }
  }

  @Test func ofTwoFoldersTheBiggestWins() throws {
    let small = model("a/Qwen-Image-2.1-PE-T2I-MLX-4bit"), big = model("a/Qwen-Image-2.1-PE-T2I-MLX-8bit")
    let sizes = [small.path: Int64(5_000), big.path: Int64(9_000)]
    #expect(try #require(enhancer(plan(models: [small, big], sizes: sizes))).model == big.name)
    #expect(try #require(enhancer(plan(models: [big, small], sizes: sizes))).model == big.name)
  }

  @Test func withoutTheModelTheGenericOneIsUsedAndTheReasonSaysSo() {
    #expect(plan(models: []) == .generic(reason: .modelMissing))
  }

  @Test func withoutTheSystemPromptFileTheGenericOneIsUsedAndTheReasonNamesTheModel() {
    #expect(plan(models: [model(t2i)], files: [:]) == .generic(reason: .systemPromptMissing(model: t2i)))
    #expect(plan(models: [model(t2i)], files: ["system_prompt.txt": "  \n "]) == .generic(reason: .systemPromptMissing(model: t2i)))
  }

  @Test func theOtherSystemPromptFileNameIsAccepted() throws {
    let chosen = try #require(enhancer(plan(models: [model(t2i)], files: ["system_prompt_t2i.txt": "T"])))
    #expect(chosen.system == "T")
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
