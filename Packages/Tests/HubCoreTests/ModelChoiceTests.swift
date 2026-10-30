import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ModelChoiceTests {
  let table = RecommendedSettings(
    models: [
      "flux_2_klein_9b": RecommendedValues(steps: 4, guidanceScale: 1, sampler: .ddimTrailing, shift: 3, resolutionDependentShift: false),
      "qwen_image_2.1": RecommendedValues(steps: 40, guidanceScale: 1, sampler: .ddimTrailing, shift: 1, resolutionDependentShift: true),
    ],
    families: ["v1": RecommendedValues(steps: 16, guidanceScale: 5, sampler: .dpmpp2mAYS, shift: 1, resolutionDependentShift: false)])

  func catalog() -> ModelCatalog {
    func model(_ file: String, _ family: String) -> CatalogModel {
      CatalogModel(file: file, name: file, family: family, capabilities: .unknown)
    }
    return ModelCatalog(
      models: [model("flux_2_klein_9b_f16.ckpt", "flux2_9b"), model("qwen_image_2.1_q8p.ckpt", "qwen_image_2.1"),
        model("juggernaut_reborn_q6p_q8p.ckpt", "v1"), model("mystery.ckpt", "mystery")],
      loras: [], fileCount: 4)
  }

  func selection() -> ModelSelection {
    ModelSelection(defaults: UserDefaults(suiteName: "ModelChoiceTests-\(UUID())")!)
  }

  @Test func choosingAnotherModelSelectsItAndReturnsTheRecommendedValues() throws {
    let selection = selection()
    var tab = GenerationParameters(width: 768, height: 1280, steps: 30, guidanceScale: 4)
    tab.loras = [LoRASelection(file: "x.ckpt")]
    let result = try #require(selection.choose("flux_2_klein_9b_f16.ckpt", applyingTo: tab, from: table, in: catalog()))
    #expect(selection.selectedFile == "flux_2_klein_9b_f16.ckpt")
    #expect(result.steps == 4 && result.sampler == .ddimTrailing && result.width == 768 && result.loras.count == 1)
  }

  @Test func choosingTheSameModelAgainChangesNothing() {
    let selection = selection()
    selection.select("flux_2_klein_9b_f16.ckpt")
    #expect(selection.choose("flux_2_klein_9b_f16.ckpt", applyingTo: GenerationParameters(steps: 30), from: table, in: catalog()) == nil)
  }

  @Test func aModelTheTableDoesNotKnowIsSelectedAndLeavesTheValues() {
    let selection = selection()
    #expect(selection.choose("mystery.ckpt", applyingTo: GenerationParameters(steps: 30), from: table, in: catalog()) == nil)
    #expect(selection.selectedFile == "mystery.ckpt")
  }

  @Test func aModelFallsBackOnItsFamilyAndSwitchingBackAppliesTheOthersAgain() throws {
    let selection = selection()
    let fine = try #require(selection.choose("juggernaut_reborn_q6p_q8p.ckpt", applyingTo: GenerationParameters(), from: table, in: catalog()))
    #expect(fine.steps == 16 && fine.guidanceScale == 5)
    let qwen = try #require(selection.choose("qwen_image_2.1_q8p.ckpt", applyingTo: fine, from: table, in: catalog()))
    #expect(qwen.steps == 40 && qwen.resolutionDependentShift)
    let klein = try #require(selection.choose("flux_2_klein_9b_f16.ckpt", applyingTo: qwen, from: table, in: catalog()))
    #expect(klein.steps == 4 && !klein.resolutionDependentShift)
  }

  @Test func selectingWithoutChoosingKeepsTheValues() {
    // What a preset, the JSON editor and "resume parameters" do: `select` alone.
    let selection = selection()
    selection.select("qwen_image_2.1_q8p.ckpt")
    #expect(selection.selectedFile == "qwen_image_2.1_q8p.ckpt")
  }

  @Test func leavingLTXForAnImageModelSwitchesTheHiresFixOffEvenWithoutATableEntry() throws {
    let video = CatalogModel(file: "ltx_2.3_q8p.ckpt", name: "LTX", family: "ltx2.3", capabilities: .unknown)
    let h3 = CatalogModel(file: "minimax_h3_q8p.ckpt", name: "H3", family: "minimax_h3", capabilities: .unknown)
    let image = CatalogModel(file: "other_image.ckpt", name: "Other", family: "flux2_9b", capabilities: .unknown)
    let catalog = ModelCatalog(models: [video, h3, image], loras: [], fileCount: 3)
    let empty = RecommendedSettings(models: [:], families: [:])
    let selection = selection()
    let ltx = try #require(selection.choose(video.file, applyingTo: GenerationParameters(), from: empty, in: catalog))
    #expect(ltx.advanced.hiresFix)
    let toImage = try #require(selection.choose(image.file, applyingTo: ltx, from: empty, in: catalog))
    #expect(toImage.advanced.hiresFix == false)
    let back = try #require(selection.choose(video.file, applyingTo: toImage, from: empty, in: catalog))
    let toH3 = try #require(selection.choose(h3.file, applyingTo: back, from: empty, in: catalog))
    #expect(toH3.advanced.hiresFix == false)
  }

  @Test func imageToImageKeepsTheHiresFix() {
    var tab = GenerationParameters()
    tab.advanced.hiresFix = true
    let selection = selection()
    selection.select("juggernaut_reborn_q6p_q8p.ckpt")
    #expect(selection.choose("mystery.ckpt", applyingTo: tab, from: table, in: catalog()) == nil)
  }
}
