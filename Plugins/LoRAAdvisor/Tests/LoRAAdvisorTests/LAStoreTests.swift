import Foundation
import Testing

@testable import LoRAAdvisor

@MainActor
struct LAStoreTests {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("la-store-\(UUID().uuidString)", isDirectory: true)
  var file: URL { folder.appendingPathComponent("loras.json") }

  func names(in sub: String) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(sub).path)) ?? []).sorted()
  }

  func write(_ text: String) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  @Test func savesAndReadsBack() {
    let store = LAStore(folder: folder)
    store.update("a.ckpt") {
      $0.link = "L"
      $0.notes = "N"
      $0.searched = true
    }
    let again = LAStore(folder: folder)
    #expect(again.entry(for: "a.ckpt") == LAEntry(link: "L", notes: "N", searched: true))
    #expect(!again.isUnreadable)
  }

  @Test func anEmptyEntryIsNotWritten() throws {
    let store = LAStore(folder: folder)
    store.update("a.ckpt") { $0.notes = "x" }
    store.update("a.ckpt") { $0.notes = "" }
    #expect(store.entries.isEmpty)
    #expect(try String(contentsOf: file, encoding: .utf8).contains("a.ckpt") == false)
  }

  @Test func aLoRATheServerLostIsKept() {
    let store = LAStore(folder: folder)
    store.update("gone.ckpt") { $0.notes = "old" }
    store.update("here.ckpt") { $0.notes = "new" }
    #expect(LAStore(folder: folder).entries.count == 2)
  }

  @Test func aMissingFileIsAnEmptyList() {
    let store = LAStore(folder: folder)
    #expect(store.entries.isEmpty && !store.isUnreadable)
    #expect(store.entry(for: "a.ckpt") == LAEntry())
  }

  @Test func anUnreadableFileIsNotOverwrittenUntilAChange() throws {
    try write("x")
    let store = LAStore(folder: folder)
    #expect(store.isUnreadable && store.entries.isEmpty)
    #expect(try String(contentsOf: file, encoding: .utf8) == "x")
    store.update("a.ckpt") { $0.notes = "n" }
    #expect(try String(contentsOf: folder.appendingPathComponent("loras.json.bak"), encoding: .utf8) == "x")
    #expect(LAStore(folder: folder).entry(for: "a.ckpt").notes == "n")
    #expect(!store.isUnreadable)
  }

  @Test func anotherSchemaIsUnreadable() throws {
    try write(#"{"schema":2,"loras":{"a.ckpt":{"notes":"n"}}}"#)
    #expect(LAStore(folder: folder).isUnreadable)
  }

  @Test func aFieldOfTheWrongTypeTakesItsDefault() throws {
    try write(#"{"schema":1,"loras":{"a.ckpt":{"notes":7,"link":"L","searched":"yes"},"b.ckpt":5}}"#)
    let store = LAStore(folder: folder)
    #expect(!store.isUnreadable)
    #expect(store.entry(for: "a.ckpt") == LAEntry(link: "L"))
    #expect(store.entries["b.ckpt"] == nil)
  }

  @Test func settingNotesByHandEndsTheRawState() {
    let store = LAStore(folder: folder)
    store.update("a.ckpt") {
      $0.notes = "raw"
      $0.rawNotes = true
    }
    store.setPageText("page", for: "a.ckpt")
    store.setNotesByUser("mie", for: "a.ckpt")
    let entry = store.entry(for: "a.ckpt")
    #expect(entry.notes == "mie" && !entry.rawNotes)
    #expect(store.pageText(for: "a.ckpt") == nil)
  }

  @Test func aNewThumbnailDeletesTheOldFile() {
    let store = LAStore(folder: folder)
    store.setThumbnail(Data([1, 2, 3]), manual: false, for: "a.ckpt")
    let first = store.entry(for: "a.ckpt").thumbnail
    store.setThumbnail(Data([4, 5]), manual: true, for: "a.ckpt")
    #expect(names(in: "thumbs").count == 1)
    #expect(store.entry(for: "a.ckpt").thumbnail != first && store.entry(for: "a.ckpt").manualThumbnail)
    #expect(store.thumbnailURL(for: "a.ckpt").flatMap { try? Data(contentsOf: $0) } == Data([4, 5]))
    store.setThumbnail(nil, manual: false, for: "a.ckpt")
    #expect(names(in: "thumbs").isEmpty)
    #expect(store.entry(for: "a.ckpt").thumbnail == nil && !store.entry(for: "a.ckpt").manualThumbnail)
    #expect(store.thumbnailURL(for: "a.ckpt") == nil)
  }

  @Test func pageTextSurvivesOddFileNames() {
    let store = LAStore(folder: folder)
    store.setPageText("t", for: "a/b: c?.ckpt")
    #expect(store.pageText(for: "a/b: c?.ckpt") == "t")
    let files = names(in: "pages")
    #expect(files.count == 1 && files[0].count == 64 + 4 && files[0].hasSuffix(".txt"))
    store.setPageText(nil, for: "a/b: c?.ckpt")
    #expect(names(in: "pages").isEmpty)
  }
}

struct StringsTests {
  @Test func everyKeyIsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) it")
      #expect(L.isDefined(key, italian: false), "\(key) en")
    }
  }
}
