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
    #expect(system.contains("src_bbox") && system.contains("Context") && system.contains("NEVER say \"preserving\""))
    #expect(system.contains("Second example (move, remove, keep)"))
    // An object taken from a reference: only the named object is described, and it is adapted to the main picture.
    #expect(system.contains("describe ONLY the object the user's text names"))
    #expect(system.contains("size, lighting, cast shadows and focus must match"))
    #expect(system.contains("ignore all of that"))
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
