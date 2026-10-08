import Foundation
import Testing

@testable import CharacterSheet

@Suite("CSTemplates")
struct CSTemplatesTests {
  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func loadReturnsTheTextWithoutOuterWhitespace() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try "\n  Role text.  \n".write(to: folder.appendingPathComponent("master-prompt.txt"), atomically: true, encoding: .utf8)
    #expect(CSTemplates.load(.master, from: folder) == .success("Role text."))
  }

  @Test func loadOfAMissingFileSaysWhich() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(CSTemplates.load(.staticPrompt, from: folder) == .failure(.missing(.staticPrompt)))
  }

  @Test func loadOfAWhitespaceOnlyFileIsEmpty() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try "  \n \n".write(to: folder.appendingPathComponent("master-prompt.txt"), atomically: true, encoding: .utf8)
    #expect(CSTemplates.load(.master, from: folder) == .failure(.empty(.master)))
  }

  @Test func fillReplacesEveryPlaceholder() {
    #expect(CSTemplates.fill("A {{name}} and {{name}}", name: "Ayaka") == "A Ayaka and Ayaka")
  }

  @Test func fillTrimsTheName() {
    #expect(CSTemplates.fill("{{name}}", name: "  Ayaka \n") == "Ayaka")
  }

  @Test func anEmptyOrBlankNameBecomesCHARACTER() {
    #expect(CSTemplates.fill("{{name}}", name: "") == "CHARACTER")
    #expect(CSTemplates.fill("{{name}}", name: "   ") == "CHARACTER")
  }

  @Test func aNameThatLooksLikeThePlaceholderIsInsertedOnce() {
    #expect(CSTemplates.fill("x {{name}} y", name: "{{name}}") == "x {{name}} y")
  }

  @Test func aNameWithQuotesIsInsertedAsIs() {
    #expect(
      CSTemplates.fill("Title \"{{name}}\"", name: "Ayaka \"the\" Kamisato") == "Title \"Ayaka \"the\" Kamisato\"")
  }

  @Test func textWithoutAPlaceholderIsUnchanged() {
    #expect(CSTemplates.fill("No placeholder", name: "Ayaka") == "No placeholder")
  }

  @Test func theFileFollowsTheSwitchAndTheSheetKind() {
    #expect(CSTemplateFile.of(useStatic: false, kind: .base) == .master)
    #expect(CSTemplateFile.of(useStatic: true, kind: .base) == .staticPrompt)
    #expect(CSTemplateFile.of(useStatic: false, kind: .expressions).rawValue == "master-prompt-expressions.txt")
    #expect(CSTemplateFile.of(useStatic: true, kind: .expressions).rawValue == "static-prompt-expressions.txt")
    #expect(CSTemplateFile.of(useStatic: false, kind: .poses).rawValue == "master-prompt-poses.txt")
    #expect(CSTemplateFile.of(useStatic: true, kind: .poses).rawValue == "static-prompt-poses.txt")
    #expect(Set(CSTemplateFile.allCases.map(\.rawValue)).count == 6)
  }

  @Test func loadReadsTheFileOfAnotherKind() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try "Faces.".write(
      to: folder.appendingPathComponent("master-prompt-expressions.txt"), atomically: true, encoding: .utf8)
    #expect(CSTemplates.load(.masterExpressions, from: folder) == .success("Faces."))
    #expect(CSTemplates.load(.masterPoses, from: folder) == .failure(.missing(.masterPoses)))
  }

  @Test func resolvedPrefersTheFileOfTheFolder() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try "  My own master.  \n".write(
      to: folder.appendingPathComponent("master-prompt.txt"), atomically: true, encoding: .utf8)
    #expect(CSTemplates.resolved(.master, from: folder) == "My own master.")
  }

  @Test func resolvedFallsBackToTheBuiltInTextWhenTheFileIsMissingOrBlank() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(CSTemplates.resolved(.masterPoses, from: folder) == CSBuiltIn.text(for: .masterPoses))
    try " \n".write(to: folder.appendingPathComponent("static-prompt.txt"), atomically: true, encoding: .utf8)
    #expect(CSTemplates.resolved(.staticPrompt, from: folder) == CSBuiltIn.text(for: .staticPrompt))
  }

  @Test func seedingWritesOnlyTheMissingFiles() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("not/yet")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "Mine.".write(to: folder.appendingPathComponent("master-prompt.txt"), atomically: true, encoding: .utf8)
    CSTemplates.seedMissing(in: folder)
    #expect(try String(contentsOf: folder.appendingPathComponent("master-prompt.txt"), encoding: .utf8) == "Mine.")
    for file in CSTemplateFile.allCases where file != .master {
      let written = try String(contentsOf: folder.appendingPathComponent(file.rawValue), encoding: .utf8)
      #expect(written.trimmingCharacters(in: .whitespacesAndNewlines) == CSBuiltIn.text(for: file), "\(file)")
    }
  }

  @Test func seedingCreatesTheFolder() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("a/b")
    CSTemplates.seedMissing(in: folder)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("static-prompt.txt").path))
  }

  @Test func defaultFolderEndsWithTheDataPath() {
    #expect(CSTemplates.defaultFolder.path.hasSuffix("DT Hub/Data/CharacterSheet"))
  }
}
