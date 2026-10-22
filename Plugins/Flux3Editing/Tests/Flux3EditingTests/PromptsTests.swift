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
    let folder = root.appendingPathComponent("prompt-master-flux3-editing", isDirectory: true)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("master-prompt.md").path))
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("custom").path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
  }

  @Test func theSystemPromptTeachesTheFormatAndTheOrderNotToTouchTheTags() {
    let root = temporaryFolder()
    EditPrompts.install(dataFolder: root)
    let system = EditPrompts.system(in: EditPrompts.folder(dataFolder: root))
    #expect(system.contains("NEVER change") && system.contains("ref_image_") && system.contains("## prose"))
    // The syntax summary, the Context list and the examples for every kind of element.
    #expect(system.contains("src_bbox") && system.contains("Context") && system.contains("NEVER say \"preserving\""))
    #expect(system.contains("Second example (move, remove, keep)"))
    #expect(EditPrompts.problems(in: EditPrompts.folder(dataFolder: root)).isEmpty)
  }

  @Test func theUsersOwnPromptIsAddedAfterTheMaster() throws {
    let root = temporaryFolder()
    EditPrompts.install(dataFolder: root)
    let custom = root.appendingPathComponent("prompt-master-flux3-editing/custom", isDirectory: true)
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
