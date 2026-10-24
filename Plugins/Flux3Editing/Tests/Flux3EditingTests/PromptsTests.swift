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
    #expect(system.contains("src_bbox") && system.contains("Context") && system.contains("Correct reply"))
    #expect(system.contains("Second example (move, remove, change)"))
    // An object taken from a reference: described as it is there, keeping identity, outfit and gear; the prose carries the effects.
    #expect(system.contains("describe the object as it is in that reference, keeping its identity, outfit and gear"))
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

/// Il master prompt E, versione 7 (spec «Migliora prompt»): scritto come lo scrivono gli annotatori di BFL: prosa = istruzione con gli
/// effetti a catena, `desc` = solo aspetto statico, fuoco mai citato se non richiesto, niente invenzioni.
struct MasterPromptV7Tests {
  private var body: String { EmbeddedData.masterPrompt }

  @Test func itIsTheSeventhEditionAndShortEnough() {
    #expect(body.hasPrefix("---\nversion: 7\n---\n"))
    let words = body.split { $0.isWhitespace }.count
    #expect(words < 1400, "\(words) words: a small model follows fewer rules better")
  }

  @Test func theProseCarriesTheEffectsAndTheClosingClause() {
    #expect(body.contains("knock-on effects"))
    #expect(body.contains("shadows, reflections, occlusion, perspective, scale, lighting"))
    #expect(body.contains("Close with one compact clause: everything else stays identical to <ref_image_0>"))
  }

  @Test func theDescriptionIsStaticAppearanceOnly() {
    #expect(body.contains("static appearance"))
    #expect(body.contains("No positions, no lighting or shadows"))
    #expect(body.contains("never \"The element\""))
  }

  @Test func focusIsNeverAddedUnlessAsked() {
    #expect(body.contains("Mention focus, depth of field or blur only if the input asks for it"))
    #expect(!body.contains("shallow focus"))
  }

  @Test func itInventsNothing() {
    #expect(body.contains("no occlusion, no actions"))
    #expect(body.contains("Keep the action the input states"))
  }

  @Test func itExplainsThePicturesAndTheBoxesAndForbidsMentioningThem() {
    #expect(body.contains("picture 1") && body.contains("canvas of the result"))
    #expect(body.contains("dashed") && body.contains("solid"))
    #expect(body.contains("never mention the pictures"))
  }

  @Test func itLetsTheBoxWinOverTheProse() {
    #expect(body.contains("follow the box"))
    #expect(body.contains("never use the words pasted, cutout or collage"))
  }

  @Test func itKeepsTheRulesTheCodeChecks() {
    #expect(body.contains("MUST be in English"))
    #expect(body.contains("between < and >"))
    #expect(body.contains("quotation marks"))
    #expect(body.contains("Correct reply"))
  }
}
