import Foundation
import Testing

@testable import AIAssistant

@Suite("Chat store")
struct ChatStoreTests {
  private func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("llmchat-\(UUID().uuidString)")
  }

  private func chat(_ title: String, updated: TimeInterval, text: String = "hello") -> Chat {
    var chat = Chat(title: title, created: Date(timeIntervalSince1970: updated), updated: Date(timeIntervalSince1970: updated))
    chat.messages = [
      ChatMessage(role: .user, text: text, date: Date(timeIntervalSince1970: updated), images: ["a.png"]),
      ChatMessage(role: .note, text: "Sent: prompt.", date: Date(timeIntervalSince1970: updated), note: .action),
    ]
    return chat
  }

  @Test func aChatRoundTrips() throws {
    let store = ChatStore(folder: folder())
    let original = chat("One", updated: 1_000_000)
    store.save(original)
    #expect(store.load(original.id) == original)
  }

  @Test func theListIsNewestFirst() {
    let store = ChatStore(folder: folder())
    let a = chat("Old", updated: 1_000)
    let b = chat("New", updated: 2_000)
    store.save(a)
    store.save(b)
    #expect(store.list().map(\.title) == ["New", "Old"])
  }

  @Test func deleteRemovesTheFile() {
    let dir = folder()
    let store = ChatStore(folder: dir)
    let a = chat("A", updated: 1)
    store.save(a)
    store.delete(a.id)
    #expect(store.load(a.id) == nil && store.list().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("chats/\(a.id.uuidString).json").path))
  }

  @Test func anUnreadableChatFileIsSkipped() throws {
    let dir = folder()
    let store = ChatStore(folder: dir)
    store.save(chat("Good", updated: 5))
    try Data("garbage".utf8).write(to: dir.appendingPathComponent("chats/x.json"))
    try Data("garbage".utf8).write(to: dir.appendingPathComponent("chats/\(UUID().uuidString).json"))
    #expect(store.list().map(\.title) == ["Good"])
  }

  @Test func brokenSettingsGiveTheDefaults() throws {
    let dir = folder()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("nope".utf8).write(to: dir.appendingPathComponent("state.json"))
    let settings = ChatStore(folder: dir).loadSettings()
    #expect(settings == ChatSettings() && settings.includeImages)
  }

  @Test func settingsRoundTripAndAPartialFileTakesDefaults() throws {
    let dir = folder()
    let store = ChatStore(folder: dir)
    let id = UUID()
    store.save(ChatSettings(currentChat: id, model: "m", includeImages: false))
    #expect(store.loadSettings() == ChatSettings(currentChat: id, model: "m", includeImages: false))
    try Data(#"{"model":"x"}"#.utf8).write(to: dir.appendingPathComponent("state.json"))
    #expect(store.loadSettings() == ChatSettings(model: "x"))
  }

  @Test func twoProjectsDoNotSeeEachOther() {
    let a = ChatStore(folder: folder())
    let b = ChatStore(folder: folder())
    a.save(chat("Mine", updated: 1))
    #expect(b.list().isEmpty)
  }

  @Test func withoutAFolderEverythingIsKeptInMemory() {
    let store = ChatStore(folder: nil)
    let a = chat("Memory", updated: 3)
    store.save(a)
    store.save(ChatSettings(model: "m"))
    #expect(store.load(a.id) == a && store.list().count == 1 && store.loadSettings().model == "m")
    store.delete(a.id)
    #expect(store.list().isEmpty)
  }

  @Test func aMessageWithMissingFieldsStillLoads() throws {
    let dir = folder()
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("chats"), withIntermediateDirectories: true)
    let id = UUID()
    let json = #"{"id":"\#(id.uuidString)","title":"T","messages":[{"role":"user","text":"hi"},{"text":"no role"}]}"#
    try Data(json.utf8).write(to: dir.appendingPathComponent("chats/\(id.uuidString).json"))
    let loaded = try #require(ChatStore(folder: dir).load(id))
    #expect(loaded.title == "T" && loaded.messages.count == 2 && loaded.messages[0].text == "hi")
  }
}
