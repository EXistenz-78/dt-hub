import Foundation
import Testing

@testable import HubCore

struct PromptLibraryTests {
  /// A fresh empty folder standing for Data/DTHub.
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("prompt-lib-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func write(_ text: String, _ path: String, in folder: URL) throws {
    let url = folder.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  let qwen = "qwen_image_2.1"

  @Test func anEmptyFolderGivesTheSystemPromptOfToday() throws {
    let library = PromptLibrary(folder: try folder())
    for (id, expected) in LegacySystemPrompts.byFamily {
      #expect(library.system(task: .enhance, family: id) == expected, Comment(rawValue: id))
      #expect(library.system(task: .describe, family: id) == expected, Comment(rawValue: id))
    }
    #expect(library.problems().isEmpty)
  }

  @Test func anUnknownOrMissingFamilyIsGeneric() throws {
    let library = PromptLibrary(folder: try folder())
    #expect(library.system(task: .enhance, family: nil) == LegacySystemPrompts.generic)
    #expect(library.system(task: .enhance, family: "no_such_family") == LegacySystemPrompts.generic)
    #expect(library.family("no_such_family") == nil && library.family(nil) == nil)
  }

  @Test func aValidFileOnDiskWins() throws {
    let dir = try folder()
    try write("---\nlabel: Mio Qwen\nmaxWords: 9\nnegative: false\nversion: 1\nwords: 1-2\n---\nSolo {words}, {maxWords}.", "family/\(qwen).md", in: dir)
    let library = PromptLibrary(folder: dir)
    #expect(library.system(task: .enhance, family: qwen) == "You write prompts for the image model \"Mio Qwen\".\n\nSolo 1-2, 9.")
    #expect(library.family(qwen)?.label == "Mio Qwen")
  }

  @Test func aLowerVersionFallsBackAndIsReported() throws {
    let dir = try folder()
    try write("---\nlabel: Vecchio\nmaxWords: 9\nnegative: false\nversion: 0\nwords: 1-2\n---\nVecchio", "family/\(qwen).md", in: dir)
    let library = PromptLibrary(folder: dir)
    #expect(library.system(task: .enhance, family: qwen) == LegacySystemPrompts.byFamily[qwen])
    #expect(library.problems().contains { $0.contains("family/\(qwen).md") })
  }

  @Test func aBrokenHeaderFallsBackAndIsReported() throws {
    let dir = try folder()
    try write("---\nlabel Qwen\n---\nTesto", "family/\(qwen).md", in: dir)
    let library = PromptLibrary(folder: dir)
    #expect(library.system(task: .enhance, family: qwen) == LegacySystemPrompts.byFamily[qwen])
    #expect(!library.problems().isEmpty)
  }

  @Test func missingWordsKeepsThePlaceholderAndIsReported() throws {
    let dir = try folder()
    try write("---\nlabel: Q\nnegative: false\nversion: 1\n---\nUsa {words} parole.", "family/\(qwen).md", in: dir)
    let library = PromptLibrary(folder: dir)
    #expect(library.system(task: .enhance, family: qwen).hasSuffix("Usa {words} parole."))
    #expect(library.problems().contains { $0.contains("{words}") })
  }

  @Test func theJSONBracesOfTheRuleAreUntouched() throws {
    let library = PromptLibrary(folder: try folder())
    #expect(library.system(task: .enhance, family: "krea_2").contains(#"{"prompt": "...", "negative": "..."}"#))
    #expect(library.family("krea_2")?.negative == true && library.family(qwen)?.negative == false)
  }

  @Test func customAppendsAfterFamilyWithThePriorityLine() throws {
    let dir = try folder()
    try write("Regola mia.", "custom/enhance.md", in: dir)
    try write("---\nmode: append\n---\nFamiglia mia.", "custom/family-\(qwen).md", in: dir)
    let library = PromptLibrary(folder: dir)
    let expected = LegacySystemPrompts.byFamily[qwen]! + "\n\n" + PromptLibrary.priorityLine + "\n\nRegola mia.\n\n"
      + PromptLibrary.priorityLine + "\n\nFamiglia mia."
    #expect(library.system(task: .enhance, family: qwen) == expected)
    #expect(library.system(task: .describe, family: qwen) == LegacySystemPrompts.byFamily[qwen]! + "\n\n" + PromptLibrary.priorityLine + "\n\nFamiglia mia.")
    #expect(library.family(qwen)?.isCustomized == true && library.family("flux1")?.isCustomized == false)
  }

  @Test func customReplaceTakesTheSlot() throws {
    let dir = try folder()
    try write("---\nmode: replace\n---\nRegole nuove per {label}.", "custom/enhance.md", in: dir)
    try write("---\nmode: replace\n---\nFamiglia nuova.", "custom/family-\(qwen).md", in: dir)
    let library = PromptLibrary(folder: dir)
    #expect(library.system(task: .enhance, family: qwen) == "Regole nuove per Qwen Image 2.1.\n\nFamiglia nuova.")
  }

  @Test func anEmptyCustomFileIsIgnored() throws {
    let dir = try folder()
    try write("   \n\n", "custom/enhance.md", in: dir)
    try write("---\nmode: append\n---\n", "custom/family-\(qwen).md", in: dir)
    let library = PromptLibrary(folder: dir)
    #expect(library.system(task: .enhance, family: qwen) == LegacySystemPrompts.byFamily[qwen])
    #expect(library.family(qwen)?.isCustomized == false)
    #expect(library.ownSystemAddition(task: .enhance) == nil)
  }

  @Test func ownSystemAdditionIsTheCustomTaskFile() throws {
    let dir = try folder()
    #expect(PromptLibrary(folder: dir).ownSystemAddition(task: .describe) == nil)
    try write("Sempre in inglese.", "custom/describe.md", in: dir)
    #expect(PromptLibrary(folder: dir).ownSystemAddition(task: .describe) == PromptLibrary.priorityLine + "\n\nSempre in inglese.")
  }

  @Test func familiesAreTheFifteenSortedByLabel() throws {
    let list = PromptLibrary(folder: try folder()).families()
    #expect(list.count == 15)
    #expect(list.map(\.label) == list.map(\.label).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    #expect(list.first { $0.id == "flux2_9b" }?.label == "FLUX.2 [klein] 9B")
    #expect(list.filter(\.negative).count == 7)
  }

  @Test func notesAreThePartAfterTheModelNotesHeading() throws {
    let family = try #require(PromptLibrary(folder: try folder()).family(qwen))
    #expect(family.notes.hasPrefix("- Length: aim for 300-450 words"))
    #expect(!family.notes.contains("Model notes:"))
  }

  @Test func editsAreReadAtEveryCall() throws {
    let dir = try folder()
    let library = PromptLibrary(folder: dir)
    let before = library.system(task: .enhance, family: qwen)
    try write("Una riga in più.", "custom/enhance.md", in: dir)
    #expect(library.system(task: .enhance, family: qwen) != before)
    try FileManager.default.removeItem(at: dir.appendingPathComponent("custom/enhance.md"))
    #expect(library.system(task: .enhance, family: qwen) == before)
  }
}
