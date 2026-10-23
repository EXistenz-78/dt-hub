import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterMOSS

struct PromptsTests {
  func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("moss-prompts-\(UUID().uuidString)") }

  @Test func installWritesTheMasterPromptAndCustomFolder() throws {
    let dir = temp()
    MossPrompts.install(dataFolder: dir)
    let folder = dir.appendingPathComponent("prompt-master-moss")
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("master-prompt.md").path))
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("custom").path, isDirectory: &isDirectory) && isDirectory.boolValue)
  }

  @Test func anOlderFileIsReplacedByTheBuiltInOne() throws {
    let dir = temp()
    let folder = dir.appendingPathComponent("prompt-master-moss")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "---\nversion: 0\n---\nold".write(to: folder.appendingPathComponent("master-prompt.md"), atomically: true, encoding: .utf8)
    MossPrompts.install(dataFolder: dir)
    let text = try String(contentsOf: folder.appendingPathComponent("master-prompt.md"), encoding: .utf8)
    #expect(!text.contains("old") && text.contains("MOSS Image"))
  }

  @Test func theSystemPromptIsTheMasterPromptWithTheRulesOfTheSpec() {
    let system = MossPrompts.system(in: MossPrompts.folder(dataFolder: temp()))
    #expect(system.contains("MOSS Image"))
    #expect(system.contains("element N (type)"))
    #expect(system.contains("never the words themselves"))
    #expect(system.contains("whatever the input language") || system.contains("MUST be in English"))
  }
}
