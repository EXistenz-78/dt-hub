import Foundation
import Testing

@testable import HubCore

struct PromptLibraryInstallTests {
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("prompt-install-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func exists(_ path: String, in dir: URL) -> Bool {
    FileManager.default.fileExists(atPath: dir.appendingPathComponent(path).path)
  }

  func text(_ path: String, in dir: URL) -> String? {
    try? String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
  }

  @Test func installWritesEveryBaseFileAndCustom() throws {
    let dir = try folder()
    PromptLibrary(folder: dir).install()
    for id in EmbeddedPrompts.families.keys { #expect(exists("family/\(id).md", in: dir), Comment(rawValue: id)) }
    #expect(exists("rules/enhance.md", in: dir) && exists("rules/describe.md", in: dir))
    #expect(exists("custom/families.txt", in: dir))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("family").path).count == 17)
  }

  @Test func installKeepsAFileWithTheSameOrHigherVersion() throws {
    let dir = try folder()
    PromptLibrary(folder: dir).install()
    let mine = "---\nlabel: Mio\nmaxWords: 9\nnegative: false\nversion: 5\nwords: 1-2\n---\nMio testo"
    try mine.write(to: dir.appendingPathComponent("family/qwen_image_2.1.md"), atomically: true, encoding: .utf8)
    PromptLibrary(folder: dir).install()
    #expect(text("family/qwen_image_2.1.md", in: dir) == mine)
    #expect(!exists("family/qwen_image_2.1.md.bak", in: dir))
  }

  @Test func installRewritesALowerVersionAndKeepsABackup() throws {
    let dir = try folder()
    PromptLibrary(folder: dir).install()
    let old = "---\nlabel: Vecchio\nmaxWords: 9\nnegative: false\nversion: 0\nwords: 1-2\n---\nVecchio"
    try old.write(to: dir.appendingPathComponent("family/qwen_image_2.1.md"), atomically: true, encoding: .utf8)
    PromptLibrary(folder: dir).install()
    #expect(text("family/qwen_image_2.1.md.bak", in: dir) == old)
    #expect(text("family/qwen_image_2.1.md", in: dir) == EmbeddedPrompts.families["qwen_image_2.1"])
  }

  @Test func installRewritesABrokenFile() throws {
    let dir = try folder()
    PromptLibrary(folder: dir).install()
    try "---\nrotto".write(to: dir.appendingPathComponent("rules/enhance.md"), atomically: true, encoding: .utf8)
    PromptLibrary(folder: dir).install()
    #expect(text("rules/enhance.md", in: dir) == EmbeddedPrompts.rules["enhance"])
    #expect(exists("rules/enhance.md.bak", in: dir))
  }

  @Test func theFamiliesListIsAlwaysRewrittenAndNamesEveryFamily() throws {
    let dir = try folder()
    PromptLibrary(folder: dir).install()
    try "vecchio".write(to: dir.appendingPathComponent("custom/families.txt"), atomically: true, encoding: .utf8)
    PromptLibrary(folder: dir).install()
    let list = try #require(text("custom/families.txt", in: dir))
    #expect(list.contains("Qwen Image 2.1 = qwen_image_2.1 (no negative prompt)"))
    #expect(list.contains("Krea 2 = krea_2 (negative prompt)"))
    #expect(list.contains("family-<id>.md") && list.contains("mode: replace"))
    #expect(!list.contains("vecchio"))
  }

  @Test func installOnAReadOnlyFolderDoesNotThrow() throws {
    let dir = try folder()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
    let library = PromptLibrary(folder: dir)
    library.install()
    #expect(library.system(task: .enhance, family: "qwen_image_2.1") == LegacySystemPrompts.byFamily["qwen_image_2.1"])
  }

  @Test func afterInstallTheSystemPromptIsStillTheOneOfToday() throws {
    let dir = try folder()
    let library = PromptLibrary(folder: dir)
    library.install()
    for (id, expected) in LegacySystemPrompts.byFamily {
      #expect(library.system(task: .enhance, family: id) == expected, Comment(rawValue: id))
    }
    #expect(library.problems().isEmpty)
  }
}
