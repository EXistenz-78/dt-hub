import Foundation
import Testing

@testable import PromptMasterMOSS

/// Un deposito in memoria: i test non toccano le preferenze dell'utente.
final class MemoryStorage: MossStorage, @unchecked Sendable {
  var values: [String: Data] = [:]
  func data(forKey key: String) -> Data? { values[key] }
  func set(_ data: Data, forKey key: String) { values[key] = data }
}

struct StoreTests {
  @Test func saveThenLoadReturnsTheSameSession() {
    let storage = MemoryStorage()
    var session = MossSession()
    session.document.description = "Una foresta"
    session.document.items = [
      MossItem(id: 1, label: .panel, caption: "c", text: "", tags: "", colors: [], box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1), expanded: true)
    ]
    session.openGroups = ["A"]
    MossStore(storage: storage).save(session)
    #expect(MossStore(storage: storage).load() == session)
  }

  @Test func aSessionOfAnotherSchemaIsIgnored() throws {
    let storage = MemoryStorage()
    var session = MossSession()
    session.schema = 99
    session.document.description = "x"
    storage.set(try JSONEncoder().encode(session), forKey: MossStore.key)
    #expect(MossStore(storage: storage).load() == MossSession())
  }

  @Test func aMissingFileGivesAnEmptySession() {
    #expect(MossStore(storage: MemoryStorage()).load() == MossSession())
  }

  @Test func theFileStorageWritesStateJSONInTheProjectFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moss-store-\(UUID().uuidString)")
    var session = MossSession()
    session.document.description = "dal file"
    MossStore(storage: FileStorage(folder: folder)).save(session)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json").path))
    #expect(MossStore(storage: FileStorage(folder: folder)).load().document.description == "dal file")
  }

  @Test func theFirstProjectAdoptsTheSessionOfBeforeProjects() {
    let legacy = MemoryStorage(), target = MemoryStorage()
    var session = MossSession()
    session.document.description = "prima dei progetti"
    MossStore(storage: legacy).save(session)
    MossStore(storage: target).adoptLegacy(from: legacy)
    #expect(MossStore(storage: target).load().document.description == "prima dei progetti")
  }
}
