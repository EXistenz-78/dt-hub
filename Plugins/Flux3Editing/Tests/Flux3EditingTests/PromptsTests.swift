import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct PromptsTests {
  private func temporaryFolder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

  @Test func installWritesTheMasterPromptAndTheCustomFolder() {
    let root = temporaryFolder()
    EditPrompts.install(dataFolder: root)
    let folder = root.appendingPathComponent("flux3-editing", isDirectory: true)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("master-prompt.md").path))
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("custom").path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
  }

  @Test func theFolderOfTheFirstVersionMovesToTheNewNameWithItsCustomFiles() throws {
    let root = temporaryFolder()
    let old = root.appendingPathComponent("prompt-master-flux3-editing/custom", isDirectory: true)
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try "my rule".write(to: old.appendingPathComponent("master-prompt.md"), atomically: true, encoding: .utf8)
    EditPrompts.install(dataFolder: root)
    let new = root.appendingPathComponent("flux3-editing", isDirectory: true)
    #expect(try String(contentsOf: new.appendingPathComponent("custom/master-prompt.md"), encoding: .utf8) == "my rule")
    #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("master-prompt.md").path))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("prompt-master-flux3-editing").path))
  }

  @Test func anExistingNewFolderIsNeverReplacedByTheOldOne() throws {
    let root = temporaryFolder()
    let old = root.appendingPathComponent("prompt-master-flux3-editing", isDirectory: true)
    let new = root.appendingPathComponent("flux3-editing/custom", isDirectory: true)
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
    try "new".write(to: new.appendingPathComponent("master-prompt.md"), atomically: true, encoding: .utf8)
    EditPrompts.install(dataFolder: root)
    #expect(try String(contentsOf: new.appendingPathComponent("master-prompt.md"), encoding: .utf8) == "new")
    #expect(FileManager.default.fileExists(atPath: old.path))
  }

  @Test func theSystemPromptTeachesTheFormatAndTheOrderNotToTouchTheTags() {
    let root = temporaryFolder()
    EditPrompts.install(dataFolder: root)
    let system = EditPrompts.system(in: EditPrompts.folder(dataFolder: root))
    #expect(system.contains("NEVER change") && system.contains("ref_image_") && system.contains("## prose"))
    // The syntax summary, the Context list and the examples for every kind of element.
    #expect(system.contains("src_bbox") && system.contains("Context") && system.contains("Never say it is new, generated or invented"))
    #expect(system.contains("Second example (move, remove, change, keep)"))
    // An object taken from a reference: only the named object is described, and it is made to look at home in the main picture.
    #expect(system.contains("describe ONLY the object the text names"))
    #expect(system.contains("in scale with something visible in the start picture"))
    #expect(system.contains("ignore whatever a box encloses besides the named object"))
    #expect(EditPrompts.problems(in: EditPrompts.folder(dataFolder: root)).isEmpty)
  }

  @Test func theUsersOwnPromptIsAddedAfterTheMaster() throws {
    let root = temporaryFolder()
    EditPrompts.install(dataFolder: root)
    let custom = root.appendingPathComponent("flux3-editing/custom", isDirectory: true)
    try "Always mention the lighting.".write(to: custom.appendingPathComponent("master-prompt.md"), atomically: true, encoding: .utf8)
    let system = EditPrompts.system(in: EditPrompts.folder(dataFolder: root))
    #expect(system.contains("NEVER change") && system.contains("Always mention the lighting."))
  }

  @Test func theEmbeddedCopyIsTheDataFile() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Data/master-prompt.md")
    #expect(try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .newlines) == EmbeddedData.masterPrompt.trimmingCharacters(in: .newlines))
  }
}

/// Il master prompt v6 (v5 + correzioni del banco ninja; spec «Flux3 Editing: l'LLM vede le immagini»): l'insieme prima dei pezzi, e una regola per ogni tipo di id.
struct MasterPromptV6Tests {
  private var body: String { EmbeddedData.masterPrompt }

  @Test func itIsTheSixthEditionAndNotTooLongForASmallModel() {
    #expect(body.hasPrefix("---\nversion: 6\n---\n"))
    let words = body.split { $0.isWhitespace }.count
    #expect(words < 1800, "\(words) words: a small model follows fewer rules better")
  }

  @Test func itTellsTheModelToTreatTheTextsAsOneScene() {
    #expect(body.contains("The prose speaks about the whole picture"))
    #expect(body.contains("Each element block speaks only about its own element"))
    #expect(body.contains("once"))  // the shared integration sentence goes in the prose once, not in every element
  }

  @Test func itExplainsThePicturesAndTheBoxesAndForbidsMentioningThem() {
    #expect(body.contains("picture 1") && body.contains("canvas of the result"))
    #expect(body.contains("dashed") && body.contains("solid"))
    #expect(body.contains("never mention the pictures"))
    #expect(!body.contains("is a crop of the object"))  // the v4 text about crops is gone
  }

  @Test func itHasARuleForEachKindOfElement() {
    for heading in [
      "An object taken from <ref_image_N>", "A new object", "Already in <ref_image_0>, kept or changed", "Moved", "Removed",
    ] {
      #expect(body.contains(heading), Comment(rawValue: heading))
    }
  }

  @Test func theRuleForObjectsTakenFromAReferenceDescribesTheIntegratedResultInPositiveWords() {
    #expect(body.contains("as it must look in the result"))
    #expect(body.contains("same focus") && body.contains("scale") && body.contains("shadow"))
    #expect(body.contains("never use the words pasted, cutout or collage"))
  }

  @Test func itNamesEveryObjectAndLetsTheBoxWinOverTheProse() {
    #expect(body.contains("Always name the object in its own block"))
    #expect(body.contains("never write \"the element\""))
    #expect(body.contains("follow the box"))
  }

  @Test func anObjectFromAReferenceAdaptsItsPoseAndKeepsOnlyIdentityOutfitAndGear() {
    #expect(body.contains("identity, outfit and gear are kept"))
    #expect(!body.contains("exact design, shape and visible details are kept"))
    #expect(body.contains("Adapt its pose to the scene"))
    #expect(body.contains("shadow beneath it"))
  }

  @Test func itKeepsTheRulesTheCodeChecks() {
    #expect(body.contains("MUST be in English"))
    #expect(body.contains("between < and >"))
    #expect(body.contains("quotation marks"))
    #expect(body.contains("Correct reply"))
  }
}
