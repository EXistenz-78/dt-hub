import Foundation
import Testing

@testable import PromptMasterF3

final class MemoryStorage: F3Storage, @unchecked Sendable {
  var values: [String: Data] = [:]
  func data(forKey key: String) -> Data? { values[key] }
  func set(_ data: Data, forKey key: String) { values[key] = data }
}

struct StoreTests {
  @Test func savesAndLoads() {
    let store = F3Store(storage: MemoryStorage())
    var session = F3Session()
    session.document.description = "hello"
    session.openGroups = ["A"]
    store.save(session)
    #expect(store.load().document.description == "hello")
    #expect(store.load().openGroups == ["A"])
  }

  @Test func otherSchemaStartsEmpty() throws {
    let storage = MemoryStorage()
    var session = F3Session()
    session.schema = 99
    session.document.description = "old"
    storage.values[F3Store.key] = try JSONEncoder().encode(session)
    #expect(F3Store(storage: storage).load().document.description == "")
  }

  @Test func missingFileIsEmptySession() {
    #expect(F3Store(storage: MemoryStorage()).load() == F3Session())
  }

  @Test func fileStorageKeepsOneFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = F3Store(storage: FileStorage(folder: folder))
    var session = F3Session()
    session.document.composition = "<a>"
    store.save(session)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json").path))
    #expect(store.load().document.composition == "<a>")
  }
}
