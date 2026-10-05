import Foundation
import Testing

@testable import PromptMaster

@Suite("The user's own terms")
struct CustomTermsStoreTests {
  private func makeStore() -> CustomTermsStore {
    CustomTermsStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("pm-custom-\(UUID().uuidString)"))
  }

  @Test func aTermIsAddedAndComesBackInANewStore() throws {
    let store = makeStore()
    #expect(store.load().isEmpty)
    let term = try store.add(text: "  luce da finestra  ", to: "light_source")
    #expect(term.text == "luce da finestra" && term.categoryID == "light_source" && term.id.hasPrefix("custom-"))
    #expect(CustomTermsStore(folder: store.folder).load() == [term])
  }

  @Test func theSameTextInTheSameCategoryIsNotAddedTwiceButInAnotherIs() throws {
    let store = makeStore()
    let first = try store.add(text: "Foggy", to: "time_weather")
    #expect(try store.add(text: "foggy", to: "time_weather") == first)
    let other = try store.add(text: "Foggy", to: "mood")
    #expect(other != first && store.load().count == 2)
  }

  @Test func anEmptyTextIsRefusedAndALongOneIsCut() throws {
    let store = makeStore()
    #expect(throws: CustomTermsStore.Failure.empty) { try store.add(text: "  \n ", to: "mood") }
    let long = try store.add(text: String(repeating: "a", count: 500), to: "mood")
    #expect(long.text.count == CustomTermsStore.maxLength)
  }

  @Test func aTermCanBeRemovedAndRemovingAnUnknownOneChangesNothing() throws {
    let store = makeStore()
    let one = try store.add(text: "one", to: "mood")
    let two = try store.add(text: "two", to: "mood")
    try store.remove(id: one.id)
    try store.remove(id: "custom-nothing")
    #expect(store.load() == [two])
  }

  @Test func anUnreadableFileIsNeverOverwritten() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    let file = store.folder.appendingPathComponent("custom-terms.json")
    try Data("not json".utf8).write(to: file)
    #expect(store.load().isEmpty)
    #expect(throws: CustomTermsStore.Failure.unreadableFile) { try store.add(text: "x", to: "mood") }
    #expect(throws: CustomTermsStore.Failure.unreadableFile) { try store.remove(id: "custom-1") }
    #expect(try Data(contentsOf: file) == Data("not json".utf8))
  }

  @Test func aFileOfAnotherLayoutIsLeftAloneToo() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    let file = store.folder.appendingPathComponent("custom-terms.json")
    try Data(#"{"schema": 2, "terms": []}"#.utf8).write(to: file)
    #expect(throws: CustomTermsStore.Failure.unreadableFile) { try store.add(text: "x", to: "mood") }
  }

  @Test func theTermsSurviveAReplacementOfTheDatabase() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-root-\(UUID().uuidString)")
    let store = CustomTermsStore(folder: root.appendingPathComponent("prompt-master"))
    let term = try store.add(text: "mine", to: "mood")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: root.appendingPathComponent("prompt-database.json"))  // the database file is replaced
    #expect(store.load() == [term])
  }
}
