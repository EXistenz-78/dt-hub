import Foundation
import Testing

@testable import DTHubPluginKit

struct DTHubPromptFolderTests {
  func dir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kit-folder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func write(_ text: String, _ path: String, in dir: URL) throws {
    let url = dir.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  func read(_ path: String, in dir: URL) -> String? {
    try? String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
  }

  let embedded = "---\nversion: 2\n---\nPer {label}."

  @Test func baseUsesTheFileWhenValidAndNotOlder() throws {
    let d = try dir()
    try write("---\nversion: 3\n---\nMio.", "rules/a.md", in: d)
    let result = DTHubPromptFolder(folder: d).base("rules/a.md", embedded: embedded)
    #expect(result.file.body == "Mio." && result.problem == nil)
  }

  @Test func baseFallsBackWithAReasonForABrokenHeaderOrAnOlderVersion() throws {
    let d = try dir()
    try write("---\nrotto", "rules/a.md", in: d)
    try write("---\nversion: 1\n---\nVecchio", "rules/b.md", in: d)
    let folder = DTHubPromptFolder(folder: d)
    for name in ["a", "b"] {
      let result = folder.base("rules/\(name).md", embedded: embedded)
      #expect(result.file.body == "Per {label}." && result.problem?.contains("rules/\(name).md") == true)
    }
    #expect(folder.base("rules/missing.md", embedded: embedded).problem == nil)
  }

  @Test func customIsNilWhenAbsentOrEmpty() throws {
    let d = try dir()
    try write("  \n", "custom/a.md", in: d)
    try write("---\nmode: append\n---\n", "custom/b.md", in: d)
    let folder = DTHubPromptFolder(folder: d)
    #expect(folder.custom("a.md") == nil && folder.custom("b.md") == nil && folder.custom("c.md") == nil)
  }

  @Test func customReadsModeReplace() throws {
    let d = try dir()
    try write("---\nmode: replace\n---\nNuovo.", "custom/a.md", in: d)
    try write("Aggiunta.", "custom/b.md", in: d)
    let folder = DTHubPromptFolder(folder: d)
    #expect(folder.custom("a.md")?.replaces == true && folder.custom("a.md")?.body == "Nuovo.")
    #expect(folder.custom("b.md")?.replaces == false)
  }

  @Test func installWritesMissingAndKeepsABackupOfAnOlderFile() throws {
    let d = try dir()
    try write("---\nversion: 1\n---\nVecchio", "rules/a.md", in: d)
    let folder = DTHubPromptFolder(folder: d)
    folder.install(["rules/a.md": embedded, "rules/b.md": embedded])
    #expect(read("rules/a.md", in: d) == embedded && read("rules/a.md.bak", in: d) == "---\nversion: 1\n---\nVecchio")
    #expect(read("rules/b.md", in: d) == embedded)
    #expect(FileManager.default.fileExists(atPath: d.appendingPathComponent("custom").path))
  }

  @Test func installKeepsAFileWithTheSameOrHigherVersion() throws {
    let d = try dir()
    let mine = "---\nversion: 2\n---\nMio testo"
    try write(mine, "rules/a.md", in: d)
    DTHubPromptFolder(folder: d).install(["rules/a.md": embedded])
    #expect(read("rules/a.md", in: d) == mine && read("rules/a.md.bak", in: d) == nil)
  }

  @Test func installOnAReadOnlyFolderDoesNotThrow() throws {
    let d = try dir()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: d.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path) }
    DTHubPromptFolder(folder: d).install(["rules/a.md": embedded])
    #expect(DTHubPromptFolder(folder: d).base("rules/a.md", embedded: embedded).file.body == "Per {label}.")
  }

  @Test func assembleJoinsRulesFamilyExtrasAndTheUsersFileLast() throws {
    let d = try dir()
    try write("Mia regola.", "custom/c.md", in: d)
    let text = DTHubPromptFolder(folder: d).assemble(
      rules: "R.", family: "F.", extras: ["E."], customName: "c.md", label: "L")
    #expect(text == "R.\n\nF.\n\nE.\n\n" + DTHubPromptFolder.priorityLine + "\n\nMia regola.")
  }

  @Test func assembleReplaceSwapsTheRules() throws {
    let d = try dir()
    try write("---\nmode: replace\n---\nRegole per {label}.", "custom/c.md", in: d)
    let text = DTHubPromptFolder(folder: d).assemble(rules: "R.", family: "F.", extras: [], customName: "c.md", label: "Qwen")
    #expect(text == "Regole per Qwen.\n\nF.")
  }

  @Test func assembleIgnoresAnEmptyUsersFile() throws {
    let d = try dir()
    try write("   ", "custom/c.md", in: d)
    #expect(DTHubPromptFolder(folder: d).assemble(rules: "R.", family: "F.", extras: [], customName: "c.md", label: "L") == "R.\n\nF.")
  }

  @Test func assembleSkipsAnEmptyFamilyText() throws {
    let d = try dir()
    #expect(DTHubPromptFolder(folder: d).assemble(rules: "R.", family: "", extras: [], customName: "c.md", label: "L") == "R.")
    try write("Mia.", "custom/c.md", in: d)
    #expect(
      DTHubPromptFolder(folder: d).assemble(rules: "R.", family: "", extras: [], customName: "c.md", label: "L")
        == "R.\n\n" + DTHubPromptFolder.priorityLine + "\n\nMia.")
  }
}
