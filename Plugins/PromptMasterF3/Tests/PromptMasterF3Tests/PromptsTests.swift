import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterF3

struct PromptsTests {
  func temporaryFolder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

  @Test func installWritesMasterPromptAndCustomFolder() {
    let root = temporaryFolder()
    F3Prompts.install(dataFolder: root)
    let folder = root.appendingPathComponent("prompt-master-f3", isDirectory: true)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("master-prompt.md").path))
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("custom").path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
  }

  @Test func systemIsTheMasterPrompt() {
    let root = temporaryFolder()
    F3Prompts.install(dataFolder: root)
    let system = F3Prompts.system(in: F3Prompts.folder(dataFolder: root))
    #expect(system.contains("NEVER change"))
    #expect(F3Prompts.problems(in: F3Prompts.folder(dataFolder: root)).isEmpty)
  }
}
