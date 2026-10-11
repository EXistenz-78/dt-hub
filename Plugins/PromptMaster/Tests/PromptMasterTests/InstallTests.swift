import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

@Suite("The prompt files of the plug-in")
struct InstallTests {
  func dataFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pm-install-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func installWritesTheTwoRulesAndCustom() throws {
    let data = try dataFolder()
    PMPrompts.install(dataFolder: data)
    let base = data.appendingPathComponent("prompt-master")
    #expect(try String(contentsOf: base.appendingPathComponent("rules/compose.md"), encoding: .utf8) == EmbeddedPrompts.compose)
    #expect(try String(contentsOf: base.appendingPathComponent("rules/compose-tags.md"), encoding: .utf8) == EmbeddedPrompts.composeTags)
    #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("custom").path))
  }

  @Test func afterInstallTheRulesAreTheSameAndNothingIsReported() throws {
    let data = try dataFolder()
    PMPrompts.install(dataFolder: data)
    let folder = PMPrompts.folder(dataFolder: data)
    #expect(PMPrompts.rules(tags: false, in: folder, label: "X") == PMPrompts.rules(tags: false, in: PMPrompts.folder(dataFolder: try dataFolder()), label: "X"))
    #expect(PMPrompts.problems(in: folder).isEmpty)
  }

  @Test func aBrokenRulesFileFallsBackAndIsReported() throws {
    let data = try dataFolder()
    PMPrompts.install(dataFolder: data)
    let url = data.appendingPathComponent("prompt-master/rules/compose.md")
    try "---\nrotto".write(to: url, atomically: true, encoding: .utf8)
    let folder = PMPrompts.folder(dataFolder: data)
    #expect(PMPrompts.rules(tags: false, in: folder, label: "Qwen").hasPrefix(#"You write prompts for the image model "Qwen"."#))
    #expect(PMPrompts.problems(in: folder).contains { $0.contains("rules/compose.md") })
  }

  @Test func readOnlyFolderDoesNotThrow() throws {
    let data = try dataFolder()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: data.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: data.path) }
    PMPrompts.install(dataFolder: data)
    #expect(PMPrompts.rules(tags: true, in: PMPrompts.folder(dataFolder: data), label: "X").contains("Do not add subjects"))
  }
}
