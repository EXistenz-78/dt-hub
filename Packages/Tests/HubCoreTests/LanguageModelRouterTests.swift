import Foundation
import HubKit
import Testing

@testable import HubCore

struct LanguageModelRouterTests {
  func model(_ name: String, vision: Bool) -> LanguageModelDescriptor {
    LanguageModelDescriptor(path: "/m/\(name)", name: name, sizeBytes: 1, supportsImages: vision)
  }
  func a(_ family: LanguageModelFamily, _ use: LanguageModelUse) -> LanguageModelAssignment {
    LanguageModelAssignment(family: family, use: use)
  }
  var all: [LanguageModelDescriptor] {
    [model("pe-t2i", vision: false), model("pe-i2i", vision: true), model("vl", vision: true), model("txt", vision: false)]
  }
  func name(_ r: Result<LanguageModelDescriptor, LanguageModelError>) -> String? { try? r.get().name }

  @Test func familyModelWinsAndOthersFallBack() {
    let table = [
      "pe-t2i": a(.family("qwen_image_2.1"), .enhance), "vl": a(.allOthers, .both),
    ]
    func pick(_ t: LanguageModelTask, _ f: String?) -> String? {
      name(LanguageModelRouter.model(for: t, family: f, models: all, assignments: table))
    }
    #expect(pick(.enhance, "qwen_image_2.1") == "pe-t2i")
    #expect(pick(.describe, "qwen_image_2.1") == "vl")
    #expect(pick(.enhance, "flux2") == "vl")
    #expect(pick(.enhance, nil) == "vl")
  }

  @Test func pluginsOnlyIsNeverChosen() {
    let table = ["pe-i2i": a(.family("qwen_image_2.1"), .pluginsOnly)]
    let r = LanguageModelRouter.model(for: .describe, family: "qwen_image_2.1", models: all, assignments: table)
    #expect(r == .failure(.noModelSelected))
  }

  @Test func describeUse() {
    let table = ["pe-i2i": a(.family("qwen_image_2.1"), .describe)]
    #expect(name(LanguageModelRouter.model(for: .describe, family: "qwen_image_2.1", models: all, assignments: table)) == "pe-i2i")
  }

  @Test func describeWithOnlyATextModelSaysImagesNotSupported() {
    let table = ["txt": a(.allOthers, .both)]
    #expect(LanguageModelRouter.model(for: .describe, family: "x", models: all, assignments: table) == .failure(.imagesNotSupported))
    #expect(name(LanguageModelRouter.model(for: .enhance, family: "x", models: all, assignments: table)) == "txt")
  }

  @Test func nothingAssigned() {
    #expect(LanguageModelRouter.model(for: .enhance, family: "x", models: all, assignments: [:]) == .failure(.noModelSelected))
    let none = ["vl": a(.none, .both)]
    #expect(LanguageModelRouter.model(for: .enhance, family: "x", models: all, assignments: none) == .failure(.noModelSelected))
  }

  @Test func duplicatesGoToTheFirstByName() {
    let table = ["vl": a(.allOthers, .both), "pe-i2i": a(.allOthers, .both)]
    // "pe-i2i" < "vl"
    #expect(name(LanguageModelRouter.model(for: .enhance, family: "x", models: all, assignments: table)) == "pe-i2i")
    #expect(LanguageModelRouter.shadowed(models: all, assignments: table) == ["vl"])
    // A text-only model does not hide a vision one: it cannot take Generate.
    let mixed = ["vl": a(.allOthers, .both), "txt": a(.allOthers, .both)]
    #expect(LanguageModelRouter.shadowed(models: all, assignments: mixed).isEmpty)
    let split = ["pe-i2i": a(.allOthers, .enhance), "vl": a(.allOthers, .both)]
    // pe-i2i wins enhance; vl wins describe: nobody is hidden.
    #expect(LanguageModelRouter.shadowed(models: all, assignments: split).isEmpty)
  }

  @Test func assignmentsOfMissingModelsAreIgnored() {
    let table = ["gone": a(.allOthers, .both)]
    #expect(LanguageModelRouter.model(for: .enhance, family: "x", models: all, assignments: table) == .failure(.noModelSelected))
  }

  @Test func needsImagesSkipsATextOnlyModelEvenForEnhance() {
    let table = ["txt": a(.family("qwen_image_2.1"), .enhance), "vl": a(.allOthers, .both)]
    func pick(_ images: Bool) -> String? {
      name(LanguageModelRouter.model(for: .enhance, family: "qwen_image_2.1", models: all, assignments: table, needs: LanguageModelNeeds(needsImages: images)))
    }
    #expect(pick(false) == "txt")
    #expect(pick(true) == "vl")
    let onlyText = ["txt": a(.allOthers, .both)]
    #expect(
      LanguageModelRouter.model(for: .enhance, family: "x", models: all, assignments: onlyText, needs: LanguageModelNeeds(needsImages: true))
        == .failure(.imagesNotSupported))
    #expect(
      LanguageModelRouter.model(for: .enhance, family: "x", models: all, assignments: [:], needs: LanguageModelNeeds(needsImages: true))
        == .failure(.noModelSelected))
  }

  // MARK: I2I / T2I

  var qwenPair: [String: LanguageModelAssignment] {
    [
      "pe-t2i": a(.family("qwen_image_2.1"), .t2i), "pe-i2i": a(.family("qwen_image_2.1"), .i2i),
      "vl": a(.allOthers, .both),
    ]
  }

  func pick(
    _ task: LanguageModelTask, _ family: String, _ table: [String: LanguageModelAssignment], hasImages: Bool,
    needsImages: Bool? = nil
  ) -> Result<LanguageModelDescriptor, LanguageModelError> {
    LanguageModelRouter.model(
      for: task, family: family, models: all, assignments: table,
      needs: LanguageModelNeeds(controlHasImages: hasImages, needsImages: needsImages ?? hasImages))
  }

  @Test func theEnhancersFollowWhatControlHolds() {
    #expect(name(pick(.enhance, "qwen_image_2.1", qwenPair, hasImages: false)) == "pe-t2i")
    #expect(name(pick(.enhance, "qwen_image_2.1", qwenPair, hasImages: true)) == "pe-i2i")
    #expect(name(pick(.describe, "qwen_image_2.1", qwenPair, hasImages: true)) == "pe-i2i")
    #expect(name(pick(.enhance, "flux2", qwenPair, hasImages: true)) == "vl")
  }

  @Test func t2iIsNeverChosenForGenerate() {
    let only = ["pe-t2i": a(.allOthers, .t2i)]
    #expect(pick(.describe, "x", only, hasImages: true) == .failure(.noModelSelected))
  }

  @Test func i2iWithoutVisionDependsOnWhetherPicturesMustBeRead() {
    let table = ["txt": a(.family("qwen_image_2.1"), .i2i)]
    #expect(pick(.enhance, "qwen_image_2.1", table, hasImages: true, needsImages: true) == .failure(.imagesNotSupported))
    #expect(name(pick(.enhance, "qwen_image_2.1", table, hasImages: true, needsImages: false)) == "txt")
  }

  @Test func theT2iI2iPairHidesNobody() {
    #expect(LanguageModelRouter.shadowed(models: all, assignments: qwenPair).isEmpty)
  }

  @Test func twoI2iOnTheSameFamilyHideTheSecond() {
    let table = ["pe-i2i": a(.family("qwen_image_2.1"), .i2i), "vl": a(.family("qwen_image_2.1"), .i2i)]
    #expect(LanguageModelRouter.shadowed(models: all, assignments: table) == ["vl"])
  }

  @Test func aT2iAndAnEnhanceOnTheSameFamily() {
    // "pe-t2i" < "txt": the T2I one wins with an empty Control; the Enhance one still wins with pictures.
    let table = ["pe-t2i": a(.family("qwen_image_2.1"), .t2i), "txt": a(.family("qwen_image_2.1"), .enhance)]
    #expect(LanguageModelRouter.shadowed(models: all, assignments: table).isEmpty)
  }
}
