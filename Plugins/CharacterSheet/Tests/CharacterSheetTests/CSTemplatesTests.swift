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

  @Test func defaultFolderEndsWithTheDataPath() {
    #expect(CSTemplates.defaultFolder.path.hasSuffix("DT Hub/Data/CharacterSheet"))
  }
}
